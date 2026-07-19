// acuity-sync-calendars — Vincula (y opcionalmente CREA) los usuarios de
// KuraTracker a partir de los calendarios de Acuity, usando el EMAIL como
// llave. Evita tener que buscar/copiar los IDs de calendario a mano.
//
// Modo 1 (por defecto, seguro): solo MAPEA por email.
//   - GET /calendars en Acuity (cada calendario trae id, name, email).
//   - Si el email coincide con el perfil de un Kurador existente, setea
//     staff.acuity_calendar_id = calendar.id.
//   - Reporta matched / unmatched (los unmatched son proveedores de Acuity que
//     todavía no existen como usuario en KuraTracker).
//
// Modo 2 (opt-in): además CREA los usuarios faltantes con cuenta de acceso.
//   Body: { "createMissing": true, "organizationId": "<uuid del centro>" }
//   - Por cada calendario sin usuario: invita por email (Supabase Auth),
//     crea el profile (rol 'clinico') y el staff (con acuity_calendar_id),
//     en la organización indicada.
//
// MULTI-ORGANIZACIÓN (estructura a futuro): `organizationId` es un parámetro,
// no está hardcodeado, para que cada centro pueda ejecutar su propia sync. Hoy
// las credenciales de Acuity son una sola cuenta (secrets). Cuando otras
// organizaciones conecten SU propia cuenta de Acuity, el siguiente paso es
// guardar credenciales por-organización (tabla organization_acuity_credentials
// + OAuth2) y que proxy/webhook/sync las usen según la org — ver README.
//
// Escribe en PRODUCCIÓN (service role). No toca el modo demo.
// Deploy:  supabase functions deploy acuity-sync-calendars

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const USER_ID = Deno.env.get("ACUITY_USER_ID") ?? "";
const API_KEY = Deno.env.get("ACUITY_API_KEY") ?? "";
const AUTH = btoa(`${USER_ID}:${API_KEY}`);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

serve(async (req) => {
  if (!USER_ID || !API_KEY) {
    return json({ error: "Acuity no configurado (faltan secrets)." }, 503);
  }

  let createMissing = false;
  let organizationId: string | null = null;
  try {
    const body = await req.json();
    createMissing = body?.createMissing === true;
    organizationId = body?.organizationId ?? null;
  } catch (_) {
    // sin body => modo mapeo únicamente
  }
  if (createMissing && !organizationId) {
    return json({ error: "createMissing requiere organizationId." }, 400);
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
    const staffRel = (p as { staff?: Array<{ id: string }> }).staff;
    const staffId = staffRel && staffRel.length > 0 ? staffRel[0].id : null;
    if (email && staffId) staffByEmail.set(email, staffId);
  }

  const matched: Array<Record<string, unknown>> = [];
  const created: Array<Record<string, unknown>> = [];
  const skipped: Array<Record<string, unknown>> = [];

  for (const c of calendars) {
    const email = (c.email as string | null)?.toLowerCase() ?? "";
    const name = (c.name as string | null) ?? "";
    if (!email) {
      skipped.push({ calendarId: c.id, name, reason: "calendario sin email" });
      continue;
    }

    const existingStaffId = staffByEmail.get(email);
    if (existingStaffId) {
      const { error } = await supabase
        .from("staff")
        .update({ acuity_calendar_id: c.id })
        .eq("id", existingStaffId);
      matched.push({ email, calendarId: c.id, name, staffId: existingStaffId, error: error?.message });
      continue;
    }

    if (!createMissing) {
      skipped.push({ email, calendarId: c.id, name, reason: "no existe usuario (usa createMissing)" });
      continue;
    }

    // --- Crear usuario con acceso ---
    // 1) Invitación de Auth (crea el usuario y envía correo para fijar contraseña).
    const invite = await supabase.auth.admin.inviteUserByEmail(email);
    if (invite.error || !invite.data.user) {
      skipped.push({ email, calendarId: c.id, name, reason: `auth: ${invite.error?.message}` });
      continue;
    }
    const uid = invite.data.user.id;
    // 2) Perfil (rol clínico) en la organización indicada.
    const pErr = (await supabase.from("profiles").insert({
      id: uid,
      organization_id: organizationId,
      role: "clinico",
      full_name: name,
      email,
      is_active: true,
    })).error;
    // 3) Registro de personal + mapeo del calendario.
    const sErr = (await supabase.from("staff").insert({
      organization_id: organizationId,
      profile_id: uid,
      folio: "",
      full_name: name,
      role_title: "Kurador",
      acuity_calendar_id: c.id,
      is_active: true,
    })).error;

    if (pErr || sErr) {
      skipped.push({ email, calendarId: c.id, name, reason: `db: ${pErr?.message ?? ""} ${sErr?.message ?? ""}` });
    } else {
      created.push({ email, calendarId: c.id, name, uid });
    }
  }

  return json({ matched, created, skipped });
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
