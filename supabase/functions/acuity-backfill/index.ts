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

  // Trae TODAS las citas (incluye pasadas y canceladas). Acuity limita por
  // `max`; si tuvieras más de 1000, habría que paginar por fechas.
  const res = await fetch(
    "https://acuityscheduling.com/api/v1/appointments?max=1000&showall=true",
    { headers: { Authorization: `Basic ${AUTH}` } },
  );
  if (!res.ok) {
    return json({ error: `Acuity error ${res.status}` }, 502);
  }
  const appts = (await res.json()) as Array<Record<string, unknown>>;

  // Mapa calendarID -> {staff_id, organization_id} para resolver dueño.
  const { data: staffRows } = await supabase
    .from("staff")
    .select("id, organization_id, acuity_calendar_id")
    .not("acuity_calendar_id", "is", null);
  const byCalendar = new Map<number, { id: string; organization_id: string }>();
  for (const s of staffRows ?? []) {
    byCalendar.set(Number(s.acuity_calendar_id), {
      id: s.id as string,
      organization_id: s.organization_id as string,
    });
  }

  const rows = appts.map((a) => {
    const owner = byCalendar.get(Number(a.calendarID));
    return {
      id: a.id,
      organization_id: owner?.organization_id ?? null,
      staff_id: owner?.id ?? null,
      acuity_calendar_id: a.calendarID,
      appointment_type_id: a.appointmentTypeID,
      appointment_type: a.type,
      first_name: a.firstName,
      last_name: a.lastName,
      email: a.email,
      phone: a.phone,
      datetime: a.datetime,
      end_time: a.endTime ?? null,
      status: a.canceled === true ? "canceled" : "scheduled",
      raw: a,
      updated_at: new Date().toISOString(),
    };
  });

  if (rows.length > 0) {
    const { error } = await supabase.from("appointments").upsert(rows);
    if (error) return json({ error: `db error: ${error.message}` }, 500);
  }

  return json({ imported: rows.length });
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
