// mercadopago-sync-charge — Consulta (PULL) a Mercado Pago el estado del pago de
// un cobro, buscando por external_reference = charges.id, y concilia si está
// aprobado. Complementa al webhook (push): sirve como "Verificar pago" manual y
// como red de seguridad si la notificación no llegó.
//
// Deploy: supabase functions deploy mercadopago-sync-charge  (verify_jwt)
// Secrets: MP_MODE ('test'|'prod'), MP_ACCESS_TOKEN(_TEST).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_MODE = (Deno.env.get("MP_MODE") ?? "test").toLowerCase();
const MP_ACCESS_TOKEN = (MP_MODE === "prod"
  ? Deno.env.get("MP_ACCESS_TOKEN")
  : Deno.env.get("MP_ACCESS_TOKEN_TEST")) ?? "";

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

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "No autenticado." }, 401);
  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller.user) return json({ error: "Sesión inválida." }, 401);
  if (!MP_ACCESS_TOKEN) return json({ error: "MP no configurado." }, 500);

  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch (_) {
    return json({ error: "Body inválido." }, 400);
  }
  const chargeId = payload["chargeId"] as string | undefined;
  if (!chargeId) return json({ error: "Falta chargeId." }, 400);

  const { data: charge } = await admin
    .from("charges").select("*").eq("id", chargeId).maybeSingle();
  if (!charge) return json({ error: "Cobro no encontrado." }, 404);
  if (charge["status"] === "pagado") return json({ status: "pagado", already: true });

  // Busca pagos con este external_reference (el más reciente primero).
  const url =
    `https://api.mercadopago.com/v1/payments/search?external_reference=${encodeURIComponent(chargeId)}&sort=date_created&criteria=desc`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` } });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    console.error("MP search error", res.status, JSON.stringify(data));
    return json({ error: `MP: ${data?.message ?? res.status}` }, 502);
  }
  const results: Array<Record<string, unknown>> = data?.results ?? [];
  if (results.length === 0) return json({ status: "sin_pago" });

  const approved = results.find((p) => p["status"] === "approved");
  const pay = approved ?? results[0];
  const status = pay["status"] as string;
  const nowIso = new Date().toISOString();
  const orgId = charge["organization_id"] as string;
  const mpPaymentId = String(pay["id"]);

  // Upsert en la bandeja de conciliación (idempotente por mp_payment_id).
  const { data: existing } = await admin
    .from("point_payments").select("id").eq("mp_payment_id", mpPaymentId).maybeSingle();
  const row = {
    organization_id: orgId,
    provider: "mercadopago",
    mp_payment_id: mpPaymentId,
    amount: Number(pay["transaction_amount"] ?? 0),
    currency: pay["currency_id"] ?? "MXN",
    status,
    method: pay["payment_type_id"] ?? null,
    external_reference: chargeId,
    description: pay["description"] ?? "Pago Mercado Pago",
    captured_at: pay["date_approved"] ?? nowIso,
    charge_id: status === "approved" ? chargeId : null,
    linked_at: status === "approved" ? nowIso : null,
    source: "sync",
    raw: pay,
    updated_at: nowIso,
  };
  if (existing) {
    await admin.from("point_payments").update(row).eq("id", existing.id);
  } else {
    await admin.from("point_payments").insert({ ...row, created_at: nowIso });
  }

  if (status === "approved") {
    await admin.from("charges").update({
      status: "pagado",
      payment_method: "tarjeta",
      payment_provider: "mercadopago",
      mp_payment_id: mpPaymentId,
      external_reference: chargeId,
      mp_status: status,
      paid_at: pay["date_approved"] ?? nowIso,
      updated_at: nowIso,
    }).eq("id", chargeId);
  }

  return json({ status });
});
