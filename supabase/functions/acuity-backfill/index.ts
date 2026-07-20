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

  // Vínculos cita->paciente ya existentes (para idempotencia: si se re-corre el
  // backfill, no se re-resuelve ni se duplican pacientes emailless).
  const { data: existingAppts } = await supabase
    .from("appointments")
    .select("id, patient_id");
  const patientByAppt = new Map<number, string | null>();
  for (const r of existingAppts ?? []) {
    patientByAppt.set(Number(r.id), (r.patient_id as string | null) ?? null);
  }

  // Recorre las citas: descarta las de calendarios no mapeados; para el resto,
  // resuelve/crea el paciente (dedup por email) y lo asigna al Kurador.
  let skipped = 0;
  let patientsLinked = 0;
  const rows: Array<Record<string, unknown>> = [];
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
    if (!patientId) {
      patientId = await resolveOrCreatePatient(supabase, {
        organizationId: owner.organization_id,
        staffId: owner.id,
        firstName: String(a.firstName ?? ""),
        lastName: String(a.lastName ?? ""),
        email: a.email ? String(a.email) : null,
      });
    }
    if (patientId) patientsLinked++;

    rows.push({
      id: a.id,
      organization_id: owner.organization_id,
      staff_id: owner.id,
      patient_id: patientId,
      acuity_calendar_id: a.calendarID,
      appointment_type_id: a.appointmentTypeID,
      appointment_type: a.type,
      first_name: a.firstName,
      last_name: a.lastName,
      email: a.email,
      phone: a.phone,
      datetime: a.datetime,
      end_time: endTimeIso,
      status: a.canceled === true ? "canceled" : "scheduled",
      raw: a,
      updated_at: new Date().toISOString(),
    });
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
