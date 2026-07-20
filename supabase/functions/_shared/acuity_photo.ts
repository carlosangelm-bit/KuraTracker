// _shared/acuity_photo.ts — Descarga la "foto de la herida" del formulario de
// admisión de Acuity (URL firmada de S3, que caduca), la comprime y la guarda
// de forma DURABLE en el bucket privado acuity-intake.
//
// La usan acuity-webhook (1 foto por cita nueva) y acuity-import-photos (lote
// para el histórico). Ambas leen la URL desde el objeto de la cita (raw.forms).
//
// Compresión (equilibrado): redimensiona el lado largo a 1600px y re-encodea
// JPEG calidad 80. Si el formato no es decodificable (p.ej. HEIC/PDF), guarda el
// original tal cual (durabilidad por encima de compresión).

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Image } from "https://deno.land/x/imagescript@1.2.17/mod.ts";

export const INTAKE_BUCKET = "acuity-intake";
export const NO_PHOTO = "no-photo";
export const PHOTO_ERROR = "error";

const MAX_SIDE = 1600;
const JPEG_QUALITY = 80;

/// URL de la foto de la herida dentro del formulario de admisión, o null.
export function extractPhotoUrl(appt: Record<string, unknown>): string | null {
  const forms = (appt.forms as unknown[]) ?? [];
  for (const f of forms) {
    if (typeof f !== "object" || f === null) continue;
    const values = ((f as Record<string, unknown>).values as unknown[]) ?? [];
    for (const v of values) {
      if (typeof v !== "object" || v === null) continue;
      const vv = v as Record<string, unknown>;
      const label = String(vv.name ?? "")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toLowerCase();
      const value = String(vv.value ?? "").trim();
      if (label.includes("foto") && /^https?:\/\//.test(value)) return value;
    }
  }
  return null;
}

/// Descarga + comprime + sube la foto. Devuelve la RUTA guardada, o [NO_PHOTO]
/// si la cita no traía foto. Lanza si la descarga/subida falla (el llamador
/// decide marcarla como [PHOTO_ERROR] para no reintentar en bucle).
/// NO escribe en la tabla appointments: eso lo hace el llamador.
export async function importIntakePhoto(
  db: SupabaseClient,
  opts: { appointmentId: number | string; organizationId: string; appt: Record<string, unknown> },
): Promise<string> {
  const url = extractPhotoUrl(opts.appt);
  if (!url) return NO_PHOTO;

  const res = await fetch(url);
  if (!res.ok) throw new Error(`descarga de foto falló (${res.status})`);
  const original = new Uint8Array(await res.arrayBuffer());

  let bytes: Uint8Array = original;
  let contentType = "image/jpeg";
  try {
    const img = await Image.decode(original);
    const longest = Math.max(img.width, img.height);
    if (longest > MAX_SIDE) {
      const scale = MAX_SIDE / longest;
      img.resize(
        Math.max(1, Math.round(img.width * scale)),
        Math.max(1, Math.round(img.height * scale)),
      );
    }
    bytes = await img.encodeJPEG(JPEG_QUALITY);
  } catch (_) {
    // Formato no decodificable: se conserva el original (durabilidad).
    bytes = original;
    contentType = res.headers.get("content-type") ?? "application/octet-stream";
  }

  const ext = extFor(contentType);
  const path = `${opts.organizationId}/${opts.appointmentId}.${ext}`;
  const up = await db.storage.from(INTAKE_BUCKET).upload(path, bytes, {
    contentType,
    upsert: true,
  });
  if (up.error) throw up.error;
  return path;
}

function extFor(ct: string): string {
  if (ct.includes("jpeg") || ct.includes("jpg")) return "jpg";
  if (ct.includes("png")) return "png";
  if (ct.includes("webp")) return "webp";
  if (ct.includes("heic") || ct.includes("heif")) return "heic";
  return "img";
}
