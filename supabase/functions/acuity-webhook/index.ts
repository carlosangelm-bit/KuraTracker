// acuity-webhook — Receptor de webhooks de Acuity que sincroniza las citas en
// la tabla public.appointments de Supabase (para lectura en tiempo real desde
// la app vía Realtime).
//
// IMPORTANTE: Acuity NO envía JWT de Supabase, así que esta función debe
// desplegarse SIN verificación de JWT y validar en su lugar la firma HMAC de
// Acuity:
//   supabase functions deploy acuity-webhook --no-verify-jwt
//
// Secrets requeridos (además de SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY que
// Supabase inyecta automáticamente):
//   ACUITY_USER_ID, ACUITY_API_KEY
//
// Registrar el webhook en Acuity (una vez), apuntando a esta función:
//   POST /webhooks  { "event": "appointment.scheduled",
//                     "target": "https://<proj>.supabase.co/functions/v1/acuity-webhook" }
//   (repetir para appointment.rescheduled / appointment.canceled / appointment.changed)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const USER_ID = Deno.env.get("ACUITY_USER_ID") ?? "";
const API_KEY = Deno.env.get("ACUITY_API_KEY") ?? "";
const AUTH = btoa(`${USER_ID}:${API_KEY}`);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// HMAC-SHA256 (base64) del cuerpo crudo usando la API Key como secreto,
// comparado con el header x-acuity-signature.
async function validSignature(rawBody: string, signature: string): Promise<boolean> {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(API_KEY),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const b64 = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return b64 === signature;
}

serve(async (req) => {
  const raw = await req.text();
  if (!(await validSignature(raw, req.headers.get("x-acuity-signature") ?? ""))) {
    return new Response("invalid signature", { status: 401 });
  }

  // Acuity envía application/x-www-form-urlencoded con id/action/calendarID/...
  const params = new URLSearchParams(raw);
  const id = params.get("id");
  const action = params.get("action") ?? "";
  if (!id) return new Response("missing id", { status: 400 });

  // Detalle completo de la cita.
  const acuityRes = await fetch(
    `https://acuityscheduling.com/api/v1/appointments/${id}`,
    { headers: { Authorization: `Basic ${AUTH}` } },
  );
  if (!acuityRes.ok) return new Response("acuity fetch error", { status: 502 });
  const appt = await acuityRes.json();

  // Resolver staff (Kurador) y organización desde el calendario de Acuity.
  const { data: staff } = await supabase
    .from("staff")
    .select("id, organization_id")
    .eq("acuity_calendar_id", appt.calendarID)
    .maybeSingle();

  const status = action.includes("canceled")
    ? "canceled"
    : action.includes("rescheduled")
      ? "rescheduled"
      : "scheduled";

  const { error } = await supabase.from("appointments").upsert({
    id: appt.id,
    organization_id: staff?.organization_id ?? null,
    staff_id: staff?.id ?? null,
    acuity_calendar_id: appt.calendarID,
    appointment_type_id: appt.appointmentTypeID,
    appointment_type: appt.type,
    first_name: appt.firstName,
    last_name: appt.lastName,
    email: appt.email,
    phone: appt.phone,
    datetime: appt.datetime,
    end_time: appt.endTime ?? null,
    status,
    raw: appt,
    updated_at: new Date().toISOString(),
  });
  if (error) return new Response(`db error: ${error.message}`, { status: 500 });

  return new Response("ok", { status: 200 });
});
