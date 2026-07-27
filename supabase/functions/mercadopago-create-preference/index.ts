// mercadopago-create-preference — Crea un link de pago (Checkout Pro) para un
// cobro. Sirve para cobrar en línea (y para PROBAR el pipeline de conciliación
// con las cuentas de prueba, sin terminal): el pago dispara el webhook, que lo
// liga al cobro por external_reference.
//
// La app (Flutter) la invoca con el JWT del usuario (functions.invoke lo
// adjunta). El Access Token de MP vive solo aquí (nunca en el cliente).
//
// Deploy: supabase functions deploy mercadopago-create-preference  (verify_jwt)
// Secret: MP_ACCESS_TOKEN (Supabase).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_ACCESS_TOKEN = Deno.env.get("MP_ACCESS_TOKEN") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 1) Autenticar al llamador por su JWT.
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "No autenticado." }, 401);
  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller.user) return json({ error: "Sesión inválida." }, 401);

  if (!MP_ACCESS_TOKEN) return json({ error: "MP no configurado (falta MP_ACCESS_TOKEN)." }, 500);

  // 2) Cobro.
  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch (_) {
    return json({ error: "Body inválido." }, 400);
  }
  const chargeId = payload["chargeId"] as string | undefined;
  if (!chargeId) return json({ error: "Falta chargeId." }, 400);

  const { data: charge } = await admin
    .from("charges")
    .select("*")
    .eq("id", chargeId)
    .maybeSingle();
  if (!charge) return json({ error: "Cobro no encontrado." }, 404);
  if (charge["status"] === "pagado") return json({ error: "El cobro ya está pagado." }, 409);

  const total = Number(charge["total"] ?? 0);
  if (total <= 0) return json({ error: "Monto inválido." }, 400);

  // 3) Preferencia de Checkout Pro. external_reference = id del cobro (así el
  //    webhook lo liga solo). notification_url = nuestro webhook.
  const title = (payload["title"] as string | undefined) ?? "Cobro de consulta";
  const pref = {
    items: [
      { title, quantity: 1, unit_price: total, currency_id: "MXN" },
    ],
    external_reference: chargeId,
    notification_url: `${SUPABASE_URL}/functions/v1/mercadopago-webhook`,
  };

  const mpRes = await fetch("https://api.mercadopago.com/checkout/preferences", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${MP_ACCESS_TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(pref),
  });
  const mp = await mpRes.json();
  if (!mpRes.ok) {
    console.error("MP preference error", mp);
    return json({ error: "No se pudo crear la preferencia en Mercado Pago.", detail: mp }, 502);
  }

  // 4) Deja el cobro marcado como "esperando pago" por MP.
  const nowIso = new Date().toISOString();
  await admin.from("charges").update({
    payment_provider: "mercadopago",
    external_reference: chargeId,
    mp_status: "pending",
    updated_at: nowIso,
  }).eq("id", chargeId);

  return json({
    preference_id: mp["id"],
    init_point: mp["init_point"],
    sandbox_init_point: mp["sandbox_init_point"],
  });
});
