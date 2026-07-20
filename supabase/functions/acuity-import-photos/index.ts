// acuity-import-photos — Importa por LOTES las fotos de herida del formulario de
// admisión de Acuity hacia el bucket durable acuity-intake (ver 0019). La
// descarga, la comprime y marca appointments.intake_photo_path.
//
// URLs FRESCAS (endurecido): las URLs firmadas de S3 que Acuity incluye en el
// objeto de la cita caducan en 1 HORA. Por eso, para cada cita que SÍ tenga
// foto, esta función pide una copia FRESCA de la cita a Acuity
// (GET /appointments/{id}) justo antes de descargar — igual que el webhook —,
// en vez de confiar en la URL (posiblemente caducada) guardada en
// appointments.raw. Así no hay carrera con el momento en que se pobló `raw`.
// Para saber si una cita trae foto se usa `raw` (basta la presencia del campo,
// no importa que su URL esté caducada), evitando llamadas a Acuity para las
// citas sin foto.
//
// Procesa un lote por invocación (evita el IDLE_TIMEOUT de 150s al comprimir).
// Reejecutar hasta que "remaining" sea 0.
//
// Seguridad: verify_jwt por defecto; ejecutar con la SERVICE ROLE KEY.
// Deploy:  supabase functions deploy acuity-import-photos

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { extractPhotoUrl, importIntakePhoto, NO_PHOTO, PHOTO_ERROR } from "../_shared/acuity_photo.ts";

const USER_ID = Deno.env.get("ACUITY_USER_ID") ?? "";
const API_KEY = Deno.env.get("ACUITY_API_KEY") ?? "";
const AUTH = btoa(`${USER_ID}:${API_KEY}`);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Conservador para no exceder memoria/tiempo al decodificar+comprimir imágenes.
const BATCH = 10;

serve(async (_req) => {
  if (!USER_ID || !API_KEY) {
    return json({ error: "Acuity no configurado (faltan secrets)." }, 503);
  }

  const { data: rows, error } = await supabase
    .from("appointments")
    .select("id, organization_id, raw")
    .is("intake_photo_path", null)
    .not("organization_id", "is", null)
    .limit(BATCH);
  if (error) return json({ error: `db error: ${error.message}` }, 500);

  let uploaded = 0;
  let noPhoto = 0;
  let failed = 0;

  for (const r of rows ?? []) {
    let value: string;
    // 1) ¿Esta cita trae foto? Basta la presencia del campo en `raw` (aunque su
    //    URL esté caducada) — así no llamamos a Acuity para las citas sin foto.
    const storedRaw = (r.raw ?? {}) as Record<string, unknown>;
    if (!extractPhotoUrl(storedRaw)) {
      value = NO_PHOTO;
      noPhoto++;
    } else {
      try {
        // 2) Copia FRESCA de la cita (URL de foto no caducada).
        const fresh = await fetchAppointment(r.id as number);
        value = await importIntakePhoto(supabase, {
          appointmentId: r.id as number,
          organizationId: r.organization_id as string,
          appt: fresh,
        });
        if (value === NO_PHOTO) noPhoto++;
        else uploaded++;
      } catch (_e) {
        value = PHOTO_ERROR;
        failed++;
      }
    }
    await supabase.from("appointments").update({ intake_photo_path: value }).eq("id", r.id);
  }

  const { count: remaining } = await supabase
    .from("appointments")
    .select("id", { count: "exact", head: true })
    .is("intake_photo_path", null)
    .not("organization_id", "is", null);

  return json({ uploaded, noPhoto, failed, remaining: remaining ?? 0 });
});

async function fetchAppointment(id: number): Promise<Record<string, unknown>> {
  const res = await fetch(`https://acuityscheduling.com/api/v1/appointments/${id}`, {
    headers: { Authorization: `Basic ${AUTH}` },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Acuity GET appointment ${id}: ${res.status} ${body.slice(0, 300)}`);
  }
  return (await res.json()) as Record<string, unknown>;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
