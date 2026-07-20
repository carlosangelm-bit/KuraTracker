// acuity-backfill — Carga ÚNICA de las citas ya existentes en Acuity hacia la
// tabla public.appointments (el webhook solo refleja cambios NUEVOS).
//
// Escribe en la base de PRODUCCIÓN (Supabase) vía service role. NO tiene nada
// que ver con el modo demo local de la app.
//
// Seguridad: se despliega CON verificación de JWT (default). Ejecútala una vez
// autenticándote con la SERVICE ROLE KEY del proyecto (es un JWT válido):
//   curl -X POST 'https://<REF>.supabase.co/functions/v1/acuity-backfill' \
//        -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
// (o `supabase functions invoke acuity-backfill`).
//
// Deploy:  supabase functions deploy acuity-backfill
// Secrets: reutiliza ACUITY_USER_ID / ACUITY_API_KEY ya configurados.
//
// Rendimiento (alta automática de pacientes, ver 0018_acuity_auto_patient.sql):
// a diferencia del webhook (1 cita a la vez, puede usar resolveOrCreatePatient
// de _shared/acuity_patient.ts sin problema), el backfill procesa cientos/miles
// de citas en una sola invocación y el runtime de Edge Functions corta la
// petición a los 150s de inactividad (IDLE_TIMEOUT). Resolver el paciente
// cita-por-cita (2-3 round trips a la BD cada una) excede ese límite con el
// volumen actual (~830 citas en scope). Por eso aquí la resolución de
// pacientes es en LOTE: se precargan en memoria los pacientes y asignaciones
// existentes (unas pocas queries totales), se agrupan las citas nuevas por
// email dentro del mismo centro, se insertan los pacientes nuevos en un solo
// INSERT y las asignaciones en un solo UPSERT. El caso sin email (Acuity
// normalmente siempre lo trae) sigue resolviéndose uno por uno con
// resolveOrCreatePatient, que es el camino ya usado por el webhook.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveOrCreatePatient } from "../_shared/acuity_patient.ts";

const USER_ID = Deno.env.get("ACUITY_USER_ID") ?? "";
const API_KEY = Deno.env.get("ACUITY_API_KEY") ?? "";
const AUTH = btoa(`${USER_ID}:${API_KEY}`);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

serve(async (_req) => {
  if (!USER_ID || !API_KEY) {
    return json({ error: "Acuity no configurado (faltan secrets)." }, 503);
  }

  // Trae TODAS las citas (incluye pasadas y canceladas). Se usa un `max`
  // holgado (2200, confirmado que cubre el histórico actual de Kura+); si el
  // volumen crece más allá, habría que paginar por fechas para evitar
  // timeouts de la API de Acuity con valores muy altos.
  const res = await fetch(
    "https://acuityscheduling.com/api/v1/appointments?max=2200&showall=true",
    { headers: { Authorization: `Basic ${AUTH}` } },
  );
  if (!res.ok) {
    return json({ error: `Acuity error ${res.status}` }, 502);
  }
  const appts = (await res.json()) as Array<Record<string, unknown>>;

  // Mapa calendarID -> {staff_id, organization_id} para resolver dueño.
  // SOLO staff ACTIVO con calendario mapeado: así el espejo local se queda
  // únicamente con las citas de Kuradores vigentes (no importa el histórico de
  // proveedores inactivos/no mapeados).
  const { data: staffRows } = await supabase
    .from("staff")
    .select("id, organization_id, acuity_calendar_id")
    .not("acuity_calendar_id", "is", null)
    .eq("is_active", true);
  const byCalendar = new Map<number, { id: string; organization_id: string }>();
  for (const s of staffRows ?? []) {
    byCalendar.set(Number(s.acuity_calendar_id), {
      id: s.id as string,
      organization_id: s.organization_id as string,
    });
  }
  const staffIds = [...byCalendar.values()].map((o) => o.id);
  const orgIds = [...new Set([...byCalendar.values()].map((o) => o.organization_id))];

  // Vínculos cita->paciente ya existentes (para idempotencia: si se re-corre el
  // backfill, no se re-resuelve ni se duplican pacientes).
  const { data: existingAppts } = await supabase
    .from("appointments")
    .select("id, patient_id");
  const patientByAppt = new Map<number, string | null>();
  for (const r of existingAppts ?? []) {
    patientByAppt.set(Number(r.id), (r.patient_id as string | null) ?? null);
  }

  // Precarga en memoria: pacientes existentes por (organizacion, email) de los
  // centros en scope -- evita 1 SELECT por cita.
  const patientByOrgEmail = new Map<string, string>();
  if (orgIds.length > 0) {
    const { data: existingPatients } = await supabase
      .from("patients")
      .select("id, organization_id, acuity_email")
      .in("organization_id", orgIds)
      .not("acuity_email", "is", null);
    for (const p of existingPatients ?? []) {
      const email = (p.acuity_email as string | null)?.toLowerCase();
      if (email) {
        patientByOrgEmail.set(`${p.organization_id}|${email}`, p.id as string);
      }
    }
  }

  // Precarga en memoria: asignaciones Kurador<->paciente ya existentes de los
  // Kuradores en scope -- evita 1 SELECT + 1 INSERT por cita.
  const assignmentKeys = new Set<string>();
  if (staffIds.length > 0) {
    const { data: existingAssignments } = await supabase
      .from("staff_patient_assignments")
      .select("staff_id, patient_id")
      .in("staff_id", staffIds);
    for (const a of existingAssignments ?? []) {
      assignmentKeys.add(`${a.staff_id}|${a.patient_id}`);
    }
  }

  // Contador de folio PA<year>-NNNN (mismo formato que _shared/acuity_patient.ts).
  const year = new Date().getFullYear();
  const { data: folioRows } = await supabase.from("patients").select("folio");
  let folioCount = (folioRows ?? []).filter((r: { folio: string | null }) =>
    (r.folio ?? "").startsWith(`PA${year}`)
  ).length;

  // Primera pasada: descarta citas fuera de scope, calcula end_time, y agrupa
  // (dedup) los pacientes NUEVOS a crear por (organizacion, email) -- varias
  // citas de la misma persona en este mismo lote solo generan 1 alta.
  type PendingAppt = {
    a: Record<string, unknown>;
    organizationId: string;
    staffId: string;
    endTimeIso: string | null;
    patientId: string | null;
    emailKey: string | null;
    needsNoEmailResolve: boolean;
  };
  const pending: PendingAppt[] = [];
  const newPatientsByKey = new Map<
    string,
    { organization_id: string; full_name: string; acuity_email: string; folio: string }
  >();
  let skipped = 0;

  // Primera pasada: SOLO clasifica y agrupa (dedup) los pacientes nuevos por
  // email -- ningún write ni ningún resolveOrCreatePatient aquí todavía. El
  // caso "sin email" se resuelve en una pasada separada, DESPUÉS del INSERT
  // en lote (ver mas abajo): ambos caminos calculan el folio "siguiente"
  // contando patients.folio en la BD, así que si se intercalaran, podrían
  // calcular el mismo numero de folio para dos pacientes distintos y chocar
  // con el `unique not null` de la columna.
  for (const a of appts) {
    const owner = byCalendar.get(Number(a.calendarID));
    if (!owner) {
      skipped++;
      continue;
    }
    // Acuity NO devuelve `endTime` como datetime completo, solo "HH:MM"
    // (p.ej. "12:00"), lo cual no es un timestamp válido. Se calcula a
    // partir de `datetime` (ISO completo) + `duration` en minutos.
    let endTimeIso: string | null = null;
    const dt = a.datetime as string | undefined;
    const durationMin = Number(a.duration ?? 0);
    if (dt && !Number.isNaN(durationMin) && durationMin > 0) {
      const start = new Date(dt);
      if (!Number.isNaN(start.getTime())) {
        endTimeIso = new Date(start.getTime() + durationMin * 60000).toISOString();
      }
    }

    let patientId = patientByAppt.get(Number(a.id)) ?? null;
    const email = String(a.email ?? "").trim().toLowerCase() || null;
    let emailKey: string | null = null;
    let needsNoEmailResolve = false;

    if (!patientId && email) {
      emailKey = `${owner.organization_id}|${email}`;
      patientId = patientByOrgEmail.get(emailKey) ?? null;
      if (!patientId && !newPatientsByKey.has(emailKey)) {
        const fullName =
          `${String(a.firstName ?? "")} ${String(a.lastName ?? "")}`.trim() ||
          "Paciente sin nombre";
        folioCount += 1;
        newPatientsByKey.set(emailKey, {
          organization_id: owner.organization_id,
          full_name: fullName,
          acuity_email: email,
          folio: `PA${year}-${String(folioCount).padStart(4, "0")}`,
        });
      }
    } else if (!patientId && !email) {
      // Caso raro (Acuity normalmente siempre trae email): se marca para
      // resolver/crear uno por uno DESPUÉS del INSERT en lote de abajo.
      needsNoEmailResolve = true;
    }

    pending.push({
      a,
      organizationId: owner.organization_id,
      staffId: owner.id,
      endTimeIso,
      patientId,
      emailKey,
      needsNoEmailResolve,
    });
  }

  // Alta en LOTE de los pacientes nuevos con email (1 solo INSERT).
  if (newPatientsByKey.size > 0) {
    const toInsert = [...newPatientsByKey.values()].map((p) => ({
      folio: p.folio,
      full_name: p.full_name,
      organization_id: p.organization_id,
      acuity_email: p.acuity_email,
      background_notes: "Alta automática desde Acuity Scheduling.",
      is_active: true,
    }));
    const { data: inserted, error } = await supabase
      .from("patients")
      .insert(toInsert)
      .select("id, organization_id, acuity_email");
    if (error) return json({ error: `db error creando pacientes: ${error.message}` }, 500);
    for (const p of inserted ?? []) {
      const email = (p.acuity_email as string | null)?.toLowerCase();
      if (email) {
        patientByOrgEmail.set(`${p.organization_id}|${email}`, p.id as string);
      }
    }
  }

  // Resuelve AHORA (ya insertado el lote anterior, así que el conteo de
  // folios en la BD que usa nextPatientFolio() ya lo refleja y no puede
  // chocar) los casos raros sin email, uno por uno con el helper compartido
  // (mismo camino que usa el webhook).
  for (const p of pending) {
    if (!p.needsNoEmailResolve) continue;
    const a = p.a;
    p.patientId = await resolveOrCreatePatient(supabase, {
      organizationId: p.organizationId,
      staffId: p.staffId,
      firstName: String(a.firstName ?? ""),
      lastName: String(a.lastName ?? ""),
      email: null,
    });
  }

  // Segunda pasada: resuelve el patientId definitivo de las citas que
  // quedaron pendientes de la alta en lote, y arma las filas finales de
  // appointments + las asignaciones Kurador<->paciente nuevas (dedup).
  let patientsLinked = 0;
  const newAssignments: Array<{ staff_id: string; patient_id: string }> = [];
  const rows: Array<Record<string, unknown>> = [];

  for (const p of pending) {
    let patientId = p.patientId;
    if (!patientId && p.emailKey) {
      patientId = patientByOrgEmail.get(p.emailKey) ?? null;
    }
    if (patientId) {
      patientsLinked++;
      const assignKey = `${p.staffId}|${patientId}`;
      if (!assignmentKeys.has(assignKey)) {
        assignmentKeys.add(assignKey);
        newAssignments.push({ staff_id: p.staffId, patient_id: patientId });
      }
    }

    const a = p.a;
    rows.push({
      id: a.id,
      organization_id: p.organizationId,
      staff_id: p.staffId,
      patient_id: patientId,
      acuity_calendar_id: a.calendarID,
      appointment_type_id: a.appointmentTypeID,
      appointment_type: a.type,
      first_name: a.firstName,
      last_name: a.lastName,
      email: a.email,
      phone: a.phone,
      datetime: a.datetime,
      end_time: p.endTimeIso,
      status: a.canceled === true ? "canceled" : "scheduled",
      raw: a,
      updated_at: new Date().toISOString(),
    });
  }

  // Asignaciones Kurador<->paciente en LOTE (1 solo UPSERT, ignora duplicados
  // ya existentes vía el unique(staff_id, patient_id) de 0001_core_schema.sql).
  if (newAssignments.length > 0) {
    const { error } = await supabase
      .from("staff_patient_assignments")
      .upsert(newAssignments, { onConflict: "staff_id,patient_id", ignoreDuplicates: true });
    if (error) return json({ error: `db error asignaciones: ${error.message}` }, 500);
  }

  if (rows.length > 0) {
    const { error } = await supabase.from("appointments").upsert(rows);
    if (error) return json({ error: `db error: ${error.message}` }, 500);
  }

  return json({ imported: rows.length, skipped, patientsLinked });
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
