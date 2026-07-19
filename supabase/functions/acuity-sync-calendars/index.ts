// acuity-sync-calendars — Vincula automáticamente cada calendario de Acuity al
// Kurador de KuraTracker por EMAIL (evita tener que buscar/copiar los IDs de
// calendario a mano).
//
// Qué hace:
//   1. GET /calendars en Acuity (cada calendario trae id, name, email).
//   2. Por cada calendario, busca el `profile` de KuraTracker con ese email y el
//      `staff` vinculado a ese perfil.
//   3. Si lo encuentra, setea staff.acuity_calendar_id = calendar.id.
//   4. Devuelve un reporte de mapeados y NO mapeados (para ver qué correos de
//      Acuity todavía no existen en KuraTracker).
//
// Escribe en PRODUCCIÓN (service role). No toca el modo demo.
//
// Deploy:  supabase functions deploy acuity-sync-calendars
// Ejecutar (una vez, o cada que agregues calendarios/personal):
//   curl -X POST 'https://<REF>.supabase.co/functions/v1/acuity-sync-calendars' \
//        -H "Authorization: Bearer <SERVICE_ROLE_KEY>"

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

  const res = await fetch("https://acuityscheduling.com/api/v1/calendars", {
    headers: { Authorization: `Basic ${AUTH}` },
  });
  if (!res.ok) return json({ error: `Acuity error ${res.status}` }, 502);
  const calendars = (await res.json()) as Array<Record<string, unknown>>;

  // Perfiles con email + su staff vinculado (para casar por correo).
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, email, staff:staff(id)");

  const staffByEmail = new Map<string, string>(); // email(lower) -> staff.id
  for (const p of profiles ?? []) {
    const email = (p.email as string | null)?.toLowerCase();
    // staff puede venir como array (relación) o null.
    const staffRel = (p as { staff?: Array<{ id: string }> }).staff;
    const staffId = staffRel && staffRel.length > 0 ? staffRel[0].id : null;
    if (email && staffId) staffByEmail.set(email, staffId);
  }

  const matched: Array<Record<string, unknown>> = [];
  const unmatched: Array<Record<string, unknown>> = [];

  for (const c of calendars) {
    const email = (c.email as string | null)?.toLowerCase() ?? "";
    const staffId = email ? staffByEmail.get(email) : undefined;
    if (staffId) {
      const { error } = await supabase
        .from("staff")
        .update({ acuity_calendar_id: c.id })
        .eq("id", staffId);
      if (!error) {
        matched.push({ email, calendarId: c.id, name: c.name, staffId });
      } else {
        unmatched.push({ email, calendarId: c.id, name: c.name, error: error.message });
      }
    } else {
      // Este correo de Acuity no existe (aún) como Kurador con cuenta en
      // KuraTracker — candidato para "crear usuario" (Nivel 2).
      unmatched.push({ email, calendarId: c.id, name: c.name });
    }
  }

  return json({ matched, unmatched });
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
