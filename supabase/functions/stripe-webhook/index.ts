// stripe-webhook — Recibe eventos de Stripe. Al completarse un Checkout, ingiere
// el pago en la bandeja de conciliación (provider='stripe') y marca el cobro
// Pagado por metadata.charge_id.
//
// Stripe no manda JWT de Supabase → desplegar SIN verificación de JWT:
//   supabase functions deploy stripe-webhook --no-verify-jwt
//
// Secrets (Supabase): STRIPE_WEBHOOK_SECRET (whsec_… del endpoint en el panel de
// Stripe, sección "Tu cuenta", en modo prueba mientras se valida). Si no está
// configurado, se OMITE la validación de firma (modo prueba).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// Verifica la firma de Stripe: header "Stripe-Signature: t=..,v1=..".
// signed_payload = `${t}.${rawBody}`; HMAC-SHA256(payload, whsec) hex == algún v1.
async function validStripeSignature(rawBody: string, sigHeader: string): Promise<boolean> {
  if (!STRIPE_WEBHOOK_SECRET) {
    // Secreto no configurado: se RECHAZA el evento (fallo diagnosticable, no
    // silencioso). Con la URL abierta (--no-verify-jwt), no validar dejaría que
    // cualquiera que conozca la URL liquide un cobro con un evento falso.
    console.error(
      "stripe-webhook: STRIPE_WEBHOOK_SECRET no configurado; se rechaza el evento.",
    );
    return false;
  }
  if (!sigHeader) return false;
  const parts = sigHeader.split(",").map((p) => p.trim());
  const t = parts.find((p) => p.startsWith("t="))?.slice(2);
  const v1s = parts.filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  if (!t || v1s.length === 0) return false;
  const signedPayload = `${t}.${rawBody}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(STRIPE_WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signedPayload));
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return v1s.includes(hex);
}

function ok200(msg: string) {
  return new Response(msg, { status: 200 });
}

serve(async (req) => {
  try {
    const raw = await req.text();
    const valid = await validStripeSignature(raw, req.headers.get("stripe-signature") ?? "");
    if (!valid) return new Response("invalid signature", { status: 400 });

    let event: Record<string, unknown> = {};
    try {
      event = JSON.parse(raw);
    } catch (_) {
      return ok200("bad json");
    }

    const type = event["type"] as string | undefined;
    if (type !== "checkout.session.completed" &&
        type !== "checkout.session.async_payment_succeeded") {
      return ok200("ignored");
    }

    const session = ((event["data"] as Record<string, unknown> | undefined)?.["object"] as
      Record<string, unknown> | undefined) ?? {};
    const paymentStatus = session["payment_status"] as string | undefined;
    if (paymentStatus !== "paid") return ok200("not paid yet");

    const meta = (session["metadata"] as Record<string, unknown> | undefined) ?? {};
    const chargeId = (meta["charge_id"] as string | undefined) ??
      (session["client_reference_id"] as string | undefined) ?? null;
    if (!chargeId) return ok200("no charge_id");

    const { data: charge } = await supabase
      .from("charges").select("*").eq("id", chargeId).maybeSingle();
    if (!charge) return ok200("no matching charge");

    const orgId = charge["organization_id"] as string;
    const stripePaymentId = String(
      session["payment_intent"] ?? session["id"] ?? "",
    );
    const amount = Number(session["amount_total"] ?? 0) / 100;
    const nowIso = new Date().toISOString();

    const { data: existing } = await supabase
      .from("point_payments").select("id").eq("mp_payment_id", stripePaymentId).maybeSingle();
    const row = {
      organization_id: orgId,
      provider: "stripe",
      mp_payment_id: stripePaymentId,
      amount,
      currency: (session["currency"] as string | undefined)?.toUpperCase() ?? "MXN",
      status: "approved",
      method: "card",
      external_reference: chargeId,
      description: "Pago Stripe (link)",
      captured_at: nowIso,
      charge_id: chargeId,
      linked_at: nowIso,
      source: "webhook",
      raw: session,
      updated_at: nowIso,
    };
    if (existing) {
      await supabase.from("point_payments").update(row).eq("id", existing.id);
    } else {
      await supabase.from("point_payments").insert({ ...row, created_at: nowIso });
    }

    if (charge["status"] !== "pagado") {
      await supabase.from("charges").update({
        status: "pagado",
        payment_method: "tarjeta",
        payment_provider: "stripe",
        mp_payment_id: stripePaymentId,
        external_reference: chargeId,
        mp_status: "paid",
        paid_at: nowIso,
        updated_at: nowIso,
      }).eq("id", chargeId);
    }

    return ok200("ok");
  } catch (e) {
    console.error("stripe-webhook error", e);
    return ok200("error");
  }
});
