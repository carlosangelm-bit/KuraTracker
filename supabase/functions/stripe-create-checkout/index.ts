// stripe-create-checkout — Crea una sesión de Stripe Checkout para un cobro y
// devuelve la URL (link de pago) para ENVIAR al paciente (WhatsApp/copiar). El
// paciente paga en su dispositivo; el webhook concilia el cobro.
//
// Deploy: supabase functions deploy stripe-create-checkout   (verify_jwt)
// Secrets (Supabase): STRIPE_SECRET_KEY (sk_test_… en prueba, sk_live_… en prod).
//   La llave define el entorno (test/live), no hace falta un flag de modo.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const APP_URL = Deno.env.get("APP_PUBLIC_URL") ?? "https://app.kuramas.com";

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
  if (!STRIPE_SECRET_KEY) return json({ error: "Stripe no configurado (falta STRIPE_SECRET_KEY)." }, 500);

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
  if (charge["status"] === "pagado") return json({ error: "El cobro ya está pagado." }, 409);

  const total = Number(charge["total"] ?? 0);
  if (total <= 0) return json({ error: "Monto inválido." }, 400);
  const title = (payload["title"] as string | undefined) ?? "Cobro de consulta";

  // Stripe usa form-urlencoded. Monto en centavos (MXN).
  const form = new URLSearchParams();
  form.set("mode", "payment");
  // Páginas PÚBLICAS de resultado (el paciente no entra a la app del personal).
  form.set("success_url", `${APP_URL}/pago-recibido`);
  form.set("cancel_url", `${APP_URL}/pago-cancelado`);
  form.set("client_reference_id", chargeId);
  form.set("metadata[charge_id]", chargeId);
  form.set("line_items[0][quantity]", "1");
  form.set("line_items[0][price_data][currency]", "mxn");
  form.set("line_items[0][price_data][unit_amount]", String(Math.round(total * 100)));
  form.set("line_items[0][price_data][product_data][name]", title);

  const res = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: form.toString(),
  });
  const session = await res.json().catch(() => ({}));
  if (!res.ok) {
    console.error("Stripe checkout error", res.status, JSON.stringify(session));
    const msg = session?.error?.message ?? `HTTP ${res.status}`;
    return json({ error: `Stripe rechazó la sesión: ${msg}`, detail: session }, 502);
  }

  // Marca el cobro como "esperando pago" por Stripe.
  const nowIso = new Date().toISOString();
  await admin.from("charges").update({
    payment_provider: "stripe",
    external_reference: chargeId,
    mp_status: "pending",
    updated_at: nowIso,
  }).eq("id", chargeId);

  return json({ id: session["id"], url: session["url"] });
});
