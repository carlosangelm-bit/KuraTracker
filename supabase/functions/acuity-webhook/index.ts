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
import { extractEnrichment, resolveOrCreatePatient } from "../_shared/acuity_patient.ts";
import { importIntakePhoto, PHOTO_ERROR } from "../_shared/acuity_photo.ts";
import { getAcuityAuth } from "../_shared/acuity_auth.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// HMAC-SHA256 (base64) del cuerpo crudo usando la API Key como secreto,
// comparado con el header x-acuity-signature.
async function validSignature(apiKey: string, rawBody: string, signature: string): Promise<boolean> {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(apiKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const b64 = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return b64 === signature;
}

serve(async (req) => {
  // MULTI-CENTRO: cada centro registra su webhook apuntando a
  // .../acuity-webhook?org=<uuid>, para saber de qué centro es y validar la
  // firma HMAC con SU API key. Sin `org` (webhooks de la cuenta única actual),
  // se usan las credenciales globales (fallback).
  const orgParam = new URL(req.url).searchParams.get("org");
  const auth = await getAcuityAuth(supabase, orgParam);
  if (!auth) return new Response("acuity not configured", { status: 401 });

  const raw = await req.text();
  if (!(await validSignature(auth.apiKey, raw, req.headers.get("x-acuity-signature") ?? ""))) {
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
    { headers: { Authorization: `Basic ${auth.basic}` } },
  );
  if (!acuityRes.ok) return new Response("acuity fetch error", { status: 502 });
  const appt = await acuityRes.json();

  // Resolver staff (Kurador) y organización desde el calendario de Acuity.
  // Solo Kuradores ACTIVOS con calendario mapeado; si el webhook trae `org`, se
  // acota a ese centro (evita colisión de calendarID entre cuentas distintas).
  let staffQuery = supabase
    .from("staff")
    .select("id, organization_id")
    .eq("acuity_calendar_id", appt.calendarID)
    .eq("is_active", true);
  if (orgParam) staffQuery = staffQuery.eq("organization_id", orgParam);
  const { data: staff } = await staffQuery.maybeSingle();

  // Si la cita no pertenece a un Kurador activo mapeado, no la almacenamos:
  // respondemos 200 para que Acuity NO reintente y la tabla se mantenga limpia.
  if (!staff) {
    return new Response("ok (ignorado: calendario no mapeado)", { status: 200 });
  }

  const status = action.includes("canceled")
    ? "canceled"
    : action.includes("rescheduled")
      ? "rescheduled"
      : "scheduled";

  // Acuity NO devuelve `endTime` como datetime completo, solo "HH:MM"
  // (p.ej. "12:00"), lo cual no es un timestamp válido. Se calcula a
  // partir de `datetime` (ISO completo) + `duration` en minutos.
  let endTimeIso: string | null = null;
  const durationMin = Number(appt.duration ?? 0);
  if (appt.datetime && !Number.isNaN(durationMin) && durationMin > 0) {
    const start = new Date(appt.datetime);
    if (!Number.isNaN(start.getTime())) {
      endTimeIso = new Date(start.getTime() + durationMin * 60000).toISOString();
    }
  }

  // Alta automática del paciente (dedup por email). Si la cita ya estaba
  // vinculada a un paciente (p.ej. al reagendar/cambiar), se reutiliza ese
  // vínculo en vez de resolver de nuevo.
  const { data: existingAppt } = await supabase
    .from("appointments")
    .select("patient_id")
    .eq("id", appt.id)
    .maybeSingle();
  let patientId = (existingAppt?.patient_id as string | null) ?? null;
  if (!patientId) {
    patientId = await resolveOrCreatePatient(supabase, {
      organizationId: staff.organization_id,
      staffId: staff.id,
      firstName: appt.firstName ?? "",
      lastName: appt.lastName ?? "",
      email: appt.email ?? null,
      // El webhook trae el objeto completo (con formulario de admisión), así que
      // se enriquece el expediente (cuidador, domicilio, notas...).
      enrichment: extractEnrichment(appt),
    });
  }

  const { error } = await supabase.from("appointments").upsert({
    id: appt.id,
    organization_id: staff.organization_id,
    staff_id: staff.id,
    patient_id: patientId,
    acuity_calendar_id: appt.calendarID,
    appointment_type_id: appt.appointmentTypeID,
    appointment_type: appt.type,
    first_name: appt.firstName,
    last_name: appt.lastName,
    email: appt.email,
    phone: appt.phone,
    datetime: appt.datetime,
    end_time: endTimeIso,
    status,
    raw: appt,
    updated_at: new Date().toISOString(),
  });
  if (error) return new Response(`db error: ${error.message}`, { status: 500 });

  // Foto de la herida (durable): descarga/comprime y guarda la ruta. Tolerante a
  // fallos: si algo sale mal, no se cae el webhook; acuity-import-photos puede
  // reintentar/rellenar después.
  try {
    const path = await importIntakePhoto(supabase, {
      appointmentId: appt.id,
      organizationId: staff.organization_id,
      appt,
    });
    await supabase.from("appointments").update({ intake_photo_path: path }).eq("id", appt.id);
  } catch (_) {
    await supabase.from("appointments").update({ intake_photo_path: PHOTO_ERROR }).eq("id", appt.id);
  }

  return new Response("ok", { status: 200 });
});
