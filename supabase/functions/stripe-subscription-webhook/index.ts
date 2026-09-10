// stripe-subscription-webhook — Eventos de SUSCRIPCIÓN de licencia. Endpoint y
// secreto de firma SEPARADOS de stripe-webhook (cobro a pacientes): aquel devuelve
// 200 en todos sus caminos para evitar tormentas de reintentos; la licencia
// necesita lo contrario — si el evento se pierde, hay un cliente que pagó sin
// derechos, así que aquí un fallo devuelve 5xx para que Stripe REINTENTE. Dos
// contratos de reintento opuestos no caben en la misma función.
//
// Deploy: supabase functions deploy stripe-subscription-webhook --no-verify-jwt
// Secrets (Supabase): STRIPE_SUBSCRIPTION_WEBHOOK_SECRET (whsec_… de ESTE endpoint;
//   si falta, se RECHAZA el evento — la URL está abierta), STRIPE_SECRET_KEY (para
//   resolver la suscripción en invoice.payment_failed).
//
// La escritura de derechos es ATÓMICA e idempotente: toda la lógica vive en la
// función SQL apply_stripe_subscription_event (registro del evento + upsert en la
// misma transacción). Aquí solo se traduce el evento a sus argumentos.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("STRIPE_SUBSCRIPTION_WEBHOOK_SECRET") ?? "";
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const HANDLED = new Set([
  "customer.subscription.created",
  "customer.subscription.updated",
  "customer.subscription.deleted",
  "invoice.payment_failed",
]);

async function validSignature(rawBody: string, sigHeader: string): Promise<boolean> {
  if (!WEBHOOK_SECRET) {
    // Sin secreto NO se valida nada y la URL está abierta → se rechaza (fallo
    // diagnosticable, no silencioso). Mismo criterio que stripe-webhook.
    console.error("stripe-subscription-webhook: STRIPE_SUBSCRIPTION_WEBHOOK_SECRET no configurado; se rechaza.");
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
    new TextEncoder().encode(WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signedPayload));
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return v1s.includes(hex);
}

// Trae la suscripción completa de Stripe (para invoice.payment_failed, que no la
// trae expandida). Devuelve el objeto subscription o null.
async function fetchSubscription(subId: string): Promise<Record<string, unknown> | null> {
  if (!STRIPE_SECRET_KEY) return null;
  const res = await fetch(`https://api.stripe.com/v1/subscriptions/${subId}`, {
    headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
  });
  if (!res.ok) return null;
  return await res.json().catch(() => null);
}

// De un objeto subscription arma {orgId, status, cpeIso, items[]}.
function extractFromSubscription(sub: Record<string, unknown>) {
  const meta = (sub["metadata"] as Record<string, unknown> | undefined) ?? {};
  const orgId = (meta["organization_id"] as string | undefined) ?? null;
  const status = (sub["status"] as string | undefined) ?? "unknown";
  const itemsData = ((sub["items"] as Record<string, unknown> | undefined)?.["data"] as
    Array<Record<string, unknown>> | undefined) ?? [];
  // current_period_end vive en la suscripción en versiones viejas de la API y en el
  // ITEM en las nuevas; se toma de donde exista.
  const cpe = (sub["current_period_end"] as number | undefined) ??
    (itemsData[0]?.["current_period_end"] as number | undefined);
  const cpeIso = cpe ? new Date(cpe * 1000).toISOString() : null;
  const items = itemsData.map((it) => {
    const price = (it["price"] as Record<string, unknown> | undefined) ?? {};
    return {
      lookup_key: (price["lookup_key"] as string | undefined) ?? null,
      quantity: Number(it["quantity"] ?? 1),
      subscription_item_id: (it["id"] as string | undefined) ?? null,
    };
  });
  return { orgId, status, cpeIso, items };
}

serve(async (req) => {
  const raw = await req.text();
  const valid = await validSignature(raw, req.headers.get("stripe-signature") ?? "");
  if (!valid) return new Response("invalid signature", { status: 400 });

  let event: Record<string, unknown> = {};
  try {
    event = JSON.parse(raw);
  } catch (_) {
    return new Response("bad json", { status: 400 });
  }

  const type = event["type"] as string | undefined;
  const eventId = event["id"] as string | undefined;
  if (!type || !eventId) return new Response("bad event", { status: 400 });
  if (!HANDLED.has(type)) return new Response("ignored", { status: 200 });

  const object = ((event["data"] as Record<string, unknown> | undefined)?.["object"] as
    Record<string, unknown> | undefined) ?? {};

  // Obtener SIEMPRE un objeto subscription (fuente de verdad, con items y estado).
  // checkout.session.completed NO se usa: no trae items ni cubre renovaciones.
  let sub: Record<string, unknown> | null = null;
  if (type.startsWith("customer.subscription.")) {
    sub = object;
  } else if (type === "invoice.payment_failed") {
    const subId = object["subscription"] as string | undefined;
    if (!subId) return new Response("no subscription on invoice", { status: 200 });
    sub = await fetchSubscription(subId);
    if (!sub) {
      // No se pudo resolver: que Stripe reintente (puede ser transitorio).
      console.error("stripe-subscription-webhook: no se pudo traer la suscripción", subId);
      return new Response("could not fetch subscription", { status: 502 });
    }
  }
  if (!sub) return new Response("ignored", { status: 200 });

  const { orgId, status, cpeIso, items } = extractFromSubscription(sub);
  if (!orgId) {
    // Sin metadata.organization_id no se puede mapear, y reintentar no lo arregla
    // (nunca aparecerá). Se registra y se acepta para no reintentar en vano.
    console.error("stripe-subscription-webhook: subscription sin metadata.organization_id", sub["id"]);
    return new Response("no organization_id", { status: 200 });
  }

  const { data: result, error } = await supabase.rpc("apply_stripe_subscription_event", {
    p_event_id: eventId,
    p_type: type,
    p_organization_id: orgId,
    p_subscription_status: status,
    p_current_period_end: cpeIso,
    p_items: items,
  });

  if (error) {
    // La transacción se revirtió (incluido el registro del evento): 5xx para que
    // Stripe reintente. §4.1 — un derecho no puede perderse en silencio.
    console.error("stripe-subscription-webhook: apply falló", JSON.stringify(error));
    return new Response(`apply failed: ${error.message ?? "error"}`, { status: 500 });
  }

  return new Response(String(result ?? "applied"), { status: 200 });
});
