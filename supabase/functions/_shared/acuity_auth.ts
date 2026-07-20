// _shared/acuity_auth.ts — Resuelve las credenciales de Acuity a usar en cada
// llamada, con soporte MULTI-CENTRO (Fase 2) y compatibilidad hacia atrás.
//
// Orden de resolución:
//   1) Credenciales por organización (organization_acuity_credentials, 0022),
//      si el centro conectó su propia cuenta.
//   2) Fallback a los secrets globales ACUITY_USER_ID / ACUITY_API_KEY (la
//      cuenta única actual, p.ej. Kura+), para no romper lo ya desplegado.
//
// Devuelve null si no hay ninguna credencial disponible.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface AcuityAuth {
  userId: string;
  apiKey: string;
  basic: string; // encabezado Authorization: `Basic ${basic}`
}

export async function getAcuityAuth(
  db: SupabaseClient,
  organizationId: string | null,
): Promise<AcuityAuth | null> {
  if (organizationId) {
    const { data } = await db
      .from("organization_acuity_credentials")
      .select("acuity_user_id, acuity_api_key")
      .eq("organization_id", organizationId)
      .eq("active", true)
      .maybeSingle();
    const uid = data?.acuity_user_id as string | undefined;
    const key = data?.acuity_api_key as string | undefined;
    if (uid && key) return make(uid, key);
  }
  // Fallback global (cuenta única actual).
  const gUid = Deno.env.get("ACUITY_USER_ID") ?? "";
  const gKey = Deno.env.get("ACUITY_API_KEY") ?? "";
  if (gUid && gKey) return make(gUid, gKey);
  return null;
}

function make(userId: string, apiKey: string): AcuityAuth {
  return { userId, apiKey, basic: btoa(`${userId}:${apiKey}`) };
}
