// license-checkout — Crea una sesión de Stripe Checkout en modo SUSCRIPCIÓN para
// que un admin compre asientos/módulos de licencia para SU centro, y devuelve la
// URL. NO reutiliza stripe-create-checkout (esa es del módulo Comercial: cobra a
// pacientes, mode=payment, price_data al vuelo — mezclar rompería ambas).
//
// Deploy: supabase functions deploy license-checkout   (verify_jwt)
// Secrets (Supabase): STRIPE_SECRET_KEY (sk_test_… / sk_live_…; define el entorno),
//   APP_PUBLIC_URL (SIN default: un default a prod dentro del sandbox cruza entornos
//   en silencio — si falta, 500).
//
// Entrada: { interval: "month"|"year", seats?: {clinico?, protocolo?}, modules?: [] }
// Salida:  { url }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const APP_URL = Deno.env.get("APP_PUBLIC_URL") ?? "";   // SIN default a propósito (§3.9).

// Se PINNEA la versión en cada llamada, no se depende de la de la cuenta (que es de
// 2018: ahí los items de suscripción traen `plan`, no `price`, y el mapeo por
// lookup_key se rompería en silencio). Pinnear por función deja explícito el
// contrato y no arrastra a stripe-create-checkout/stripe-webhook (API vieja, en prod).
const STRIPE_VERSION = "2026-08-26.dahlia";
const STRIPE_HEADERS = {
  Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
  "Stripe-Version": STRIPE_VERSION,
};

const SEAT_CEILING = 5;   // techo del autoservicio (kSelfServiceSeatCeiling).
const VALID_MODULES = ["admin", "insumos", "comercial"];
const VALID_SEATS = ["clinico", "protocolo"];

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

async function stripe(path: string, form: URLSearchParams) {
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: "POST",
    headers: {
      ...STRIPE_HEADERS,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: form.toString(),
  });
  const body = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, body };
}

async function getSubscription(subId: string): Promise<Record<string, unknown> | null> {
  const res = await fetch(`https://api.stripe.com/v1/subscriptions/${subId}`, {
    headers: STRIPE_HEADERS,
  });
  if (!res.ok) return null;
  return await res.json().catch(() => null);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  if (!STRIPE_SECRET_KEY) return json({ error: "Stripe no configurado (falta STRIPE_SECRET_KEY)." }, 500);
  // §3.9 — sin APP_PUBLIC_URL no se arma un link; nunca caer a app.kuramas.com.
  if (!APP_URL) return json({ error: "Falta APP_PUBLIC_URL en el entorno." }, 500);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // --- Autenticación e identidad del llamante -------------------------------
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "No autenticado." }, 401);
  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller.user) return json({ error: "Sesión inválida." }, 401);

  // §3.1 — el org SIEMPRE sale del perfil del llamante, NUNCA del body. El
  // comprador tiene que ser admin de su propio centro.
  const { data: profile } = await admin
    .from("profiles").select("id, roles, organization_id").eq("id", caller.user.id).maybeSingle();
  if (!profile) return json({ error: "Perfil no encontrado." }, 403);
  const roles: string[] = (profile["roles"] as string[] | null) ?? [];
  const orgId = profile["organization_id"] as string | null;
  if (!roles.includes("admin") || !orgId) {
    return json({ error: "Solo un administrador de un centro puede comprar licencias." }, 403);
  }

  // --- Body ------------------------------------------------------------------
  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch (_) {
    return json({ error: "Body inválido." }, 400);
  }
  const interval = payload["interval"] as string | undefined;
  if (interval !== "month" && interval !== "year") {
    return json({ error: "interval debe ser 'month' o 'year' (uno solo por suscripción)." }, 400);
  }
  const seatsIn = (payload["seats"] as Record<string, unknown> | undefined) ?? {};
  const modulesIn = (payload["modules"] as string[] | undefined) ?? [];

  // Normaliza asientos pedidos (qty >= 1).
  const seatReq: Record<string, number> = {};
  for (const k of VALID_SEATS) {
    const q = Math.trunc(Number(seatsIn[k] ?? 0));
    if (q >= 1) seatReq[k] = q;
  }
  const moduleReq = modulesIn.filter((m) => VALID_MODULES.includes(m));
  if (Object.keys(seatReq).length === 0 && moduleReq.length === 0) {
    return json({ error: "No se pidió ningún asiento ni módulo." }, 400);
  }

  // §3.4 — techo del autoservicio: >5 asientos clínicos no se vende solo; se deja
  // el rastro del lead en license_requests y se manda a cotización asistida.
  if ((seatReq["clinico"] ?? 0) > SEAT_CEILING) {
    await admin.from("license_requests").insert({
      organization_id: orgId,
      kind: "seat_clinico",
      requested_quantity: seatReq["clinico"],
      note: "Auto: checkout por encima del techo de autoservicio.",
      created_by: profile["id"],
      created_by_role: "admin",
    });
    return json({
      error: "Arriba de 5 asientos clínicos la compra es asistida; dejamos tu solicitud.",
      ceiling: SEAT_CEILING,
    }, 409);
  }

  // --- Resolver lookup_keys desde billing_catalog (única fuente) -------------
  // { lookup_key -> quantity }
  const wanted: Record<string, number> = {};
  const { data: catalog } = await admin
    .from("billing_catalog").select("lookup_key, kind, key, interval").eq("interval", interval);
  const cat = (catalog ?? []) as Array<Record<string, string>>;
  function lookupFor(kind: string, key: string): string | null {
    return cat.find((c) => c["kind"] === kind && c["key"] === key)?.["lookup_key"] ?? null;
  }
  for (const [key, qty] of Object.entries(seatReq)) {
    const lk = lookupFor("seat", key);
    if (!lk) return json({ error: `No hay tarifa de asiento '${key}' (${interval}) en el catálogo.` }, 400);
    wanted[lk] = qty;
  }
  for (const key of moduleReq) {
    const lk = lookupFor("module", key);
    if (!lk) return json({ error: `No hay tarifa de módulo '${key}' (${interval}) en el catálogo.` }, 400);
    wanted[lk] = 1;   // §3.5 — un módulo = cantidad 1.
  }

  // §3.2 — resolver los precios por CLAVE DE BÚSQUEDA (no por ID). Si Stripe no
  // devuelve alguna clave pedida, fallar con 502 diciendo cuál falta.
  const q = new URLSearchParams();
  q.set("active", "true");
  q.set("limit", "100");
  for (const lk of Object.keys(wanted)) q.append("lookup_keys[]", lk);
  const pricesRes = await fetch(`https://api.stripe.com/v1/prices?${q.toString()}`, {
    headers: STRIPE_HEADERS,
  });
  const pricesBody = await pricesRes.json().catch(() => ({}));
  if (!pricesRes.ok) {
    return json({ error: `Stripe no devolvió los precios: HTTP ${pricesRes.status}`, detail: pricesBody }, 502);
  }
  const priceByLookup: Record<string, string> = {};
  for (const p of (pricesBody["data"] as Array<Record<string, unknown>> | undefined) ?? []) {
    const lk = p["lookup_key"] as string | undefined;
    if (lk) priceByLookup[lk] = p["id"] as string;
  }
  const missing = Object.keys(wanted).filter((lk) => !priceByLookup[lk]);
  if (missing.length > 0) {
    return json({ error: `Stripe no tiene precio activo para: ${missing.join(", ")}.` }, 502);
  }

  const { data: org } = await admin
    .from("organizations")
    .select("id, name, stripe_customer_id, stripe_subscription_id")
    .eq("id", orgId).maybeSingle();

  // --- ¿Ya hay una suscripción viva? → ACTUALIZAR en vez de crear otra (§3.1) --
  // Checkout en modo suscripción SIEMPRE crea una nueva; sin esto, la 2ª compra
  // deja al centro con dos suscripciones (doble cobro, y sus eventos peleándose).
  // El prorrateo real (§3.8) vive AQUÍ, en el update, no en la creación.
  const existingSubId = (org?.["stripe_subscription_id"] as string | null) ?? null;
  if (existingSubId) {
    const sub = await getSubscription(existingSubId);
    const st = sub?.["status"] as string | undefined;
    if (sub && (st === "active" || st === "trialing" || st === "past_due")) {
      const curItems = ((sub["items"] as Record<string, unknown> | undefined)?.["data"] as
        Array<Record<string, unknown>> | undefined) ?? [];
      // Semántica de COMPRA (upsert), NO de reemplazo: lo pedido se ajusta/añade;
      // lo que NO viene en el carrito se DEJA COMO ESTÁ. Un carrito parcial (p. ej.
      // "contratar Insumos") no debe borrar los asientos ni el Protocolo vigentes.
      // Dar de baja un concepto es una acción explícita y aparte, no una omisión.
      const uForm = new URLSearchParams();
      uForm.set("proration_behavior", "create_prorations");   // §3.8 — aquí SÍ prorratea.
      uForm.set("automatic_tax[enabled]", "true");
      let ui = 0;
      for (const [lk, qty] of Object.entries(wanted)) {
        const priceId = priceByLookup[lk];
        const cur = curItems.find((it) => {
          const price = (it["price"] as Record<string, unknown> | undefined) ?? {};
          return price["id"] === priceId || price["lookup_key"] === lk;
        });
        if (cur) {
          uForm.set(`items[${ui}][id]`, cur["id"] as string);
          uForm.set(`items[${ui}][quantity]`, String(qty));
        } else {
          uForm.set(`items[${ui}][price]`, priceId);
          uForm.set(`items[${ui}][quantity]`, String(qty));
        }
        ui++;
      }
      const upd = await stripe(`subscriptions/${existingSubId}`, uForm);
      if (!upd.ok) {
        console.error("license-checkout: update de suscripción falló", upd.status, JSON.stringify(upd.body));
        const msg = (upd.body as Record<string, Record<string, unknown>>)?.["error"]?.["message"] ?? `HTTP ${upd.status}`;
        return json({ error: `Stripe rechazó la actualización: ${msg}` }, 502);
      }
      // El webhook (customer.subscription.updated) escribe los derechos nuevos; no
      // hay redirección — el método de pago ya está en archivo. Sin url.
      return json({ updated: true });
    }
    // Suscripción cancelada/expirada: cae a crear una nueva.
  }

  // --- Customer del centro: reutilizar o crear (§3.10) -----------------------
  let customerId = (org?.["stripe_customer_id"] as string | null) ?? null;
  if (!customerId) {
    const cForm = new URLSearchParams();
    cForm.set("name", (org?.["name"] as string | undefined) ?? "Centro KuraTracker");
    cForm.set("metadata[organization_id]", orgId);   // §3.7 — load-bearing.
    const created = await stripe("customers", cForm);
    if (!created.ok) {
      return json({ error: "No se pudo crear el customer de Stripe.", detail: created.body }, 502);
    }
    customerId = (created.body as Record<string, unknown>)["id"] as string;
    await admin.from("organizations").update({ stripe_customer_id: customerId }).eq("id", orgId);
  }

  // --- Sesión de Checkout en modo suscripción --------------------------------
  const form = new URLSearchParams();
  form.set("mode", "subscription");
  form.set("customer", customerId);
  form.set("success_url", `${APP_URL}/admin?checkout=success`);
  form.set("cancel_url", `${APP_URL}/admin?checkout=cancel`);
  form.set("automatic_tax[enabled]", "true");          // §3.6 — IVA incluido → desglose.
  form.set("customer_update[address]", "auto");        // requisito de automatic_tax.
  form.set("subscription_data[metadata][organization_id]", orgId);   // §3.7.
  // (Sin proration_behavior aquí: en una suscripción NUEVA no hay qué prorratear;
  //  el prorrateo del §3.8 vive en la ruta de actualización de arriba.)

  let i = 0;
  for (const [lk, qty] of Object.entries(wanted)) {
    form.set(`line_items[${i}][price]`, priceByLookup[lk]);
    form.set(`line_items[${i}][quantity]`, String(qty));
    i++;
  }

  const session = await stripe("checkout/sessions", form);
  if (!session.ok) {
    console.error("license-checkout: Stripe rechazó la sesión", session.status, JSON.stringify(session.body));
    const msg = (session.body as Record<string, Record<string, unknown>>)?.["error"]?.["message"] ?? `HTTP ${session.status}`;
    return json({ error: `Stripe rechazó la sesión: ${msg}` }, 502);
  }
  return json({ url: (session.body as Record<string, unknown>)["url"] });
});
