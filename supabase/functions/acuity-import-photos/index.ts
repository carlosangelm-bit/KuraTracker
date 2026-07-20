// acuity-import-photos — Importa por LOTES las fotos de herida del formulario de
// admisión de Acuity hacia el bucket durable acuity-intake (ver 0019). Lee la
// URL desde appointments.raw (no depende de la API de Acuity), la comprime y la
// guarda, y marca appointments.intake_photo_path.
//
// URGENTE para el histórico: las URLs de S3 de Acuity CADUCAN; correr pronto.
//
// Procesa un lote por invocación (evita el IDLE_TIMEOUT de 150s al comprimir
// imágenes). Reejecutar hasta que "remaining" sea 0.
//
// Seguridad: verify_jwt por defecto; ejecutar con la SERVICE ROLE KEY.
//   curl -X POST '.../functions/v1/acuity-import-photos' -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
// Deploy:  supabase functions deploy acuity-import-photos

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { importIntakePhoto, NO_PHOTO, PHOTO_ERROR } from "../_shared/acuity_photo.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Conservador para no exceder memoria/tiempo al decodificar+comprimir imágenes.
const BATCH = 10;

serve(async (_req) => {
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
    try {
      value = await importIntakePhoto(supabase, {
        appointmentId: r.id as number,
        organizationId: r.organization_id as string,
        appt: (r.raw ?? {}) as Record<string, unknown>,
      });
      if (value === NO_PHOTO) noPhoto++;
      else uploaded++;
    } catch (_) {
      // No se pudo descargar (p.ej. URL ya caducada): se marca para no
      // reintentar en bucle. Queda registro en background_notes de todos modos.
      value = PHOTO_ERROR;
      failed++;
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

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
