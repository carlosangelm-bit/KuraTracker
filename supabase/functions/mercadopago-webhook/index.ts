// mercadopago-webhook — Receptor de notificaciones de Mercado Pago.
//
// Ingiere cada pago aprobado en la BANDEJA DE CONCILIACIÓN (point_payments) y,
// si el external_reference calza con un cobro (charges.id), lo liga y marca el
// cobro como pagado. Sirve tanto para pagos online (Checkout Pro de prueba)
// como, en el futuro, para la terminal Point — el pipeline es el mismo.
//
// Mercado Pago NO envía JWT de Supabase → desplegar SIN verificación de JWT:
//   supabase functions deploy mercadopago-webhook --no-verify-jwt
//
// Secrets (Supabase; SUPABASE_URL/SERVICE_ROLE_KEY los inyecta Supabase):
//   MP_ACCESS_TOKEN     — para consultar el pago (GET /v1/payments/{id}).
//   MP_WEBHOOK_SECRET   — clave de firma del webhook (panel MP → Webhooks).
//                         Si NO está configurada, se OMITE la validación de
//                         firma (modo prueba). Configúrala para producción.
//
// Notas de conciliación:
//   - external_reference DEBE ser el id del cobro (charges.id); así el pago se
//     liga automáticamente. Lo fija mercadopago-create-preference.
//   - El descuento de inventario del cobro se materializa hoy en la app al
//     marcar pagado; con el webhook se marca 'pagado' aquí, y el ajuste de
//     inventario queda pendiente de reconciliar en la app (Fase 2b).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_ACCESS_TOKEN = Deno.env.get("MP_ACCESS_TOKEN") ?? "";
const MP_WEBHOOK_SECRET = Deno.env.get("MP_WEBHOOK_SECRET") ?? "";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// Valida la firma del webhook (panel MP). Manifest oficial:
//   id:<data.id>;request-id:<x-request-id>;ts:<ts>;
// HMAC-SHA256(manifest, MP_WEBHOOK_SECRET) en hex == v1 del header x-signature.
async function validSignature(
  dataId: string,
  xSignature: string,
  xRequestId: string,
): Promise<boolean> {
  if (!MP_WEBHOOK_SECRET) return true; // modo prueba: sin secreto, no se valida
  if (!xSignature) return false;
  const parts = Object.fromEntries(
    xSignature.split(",").map((p) => p.trim().split("=") as [string, string]),
  );
  const ts = parts["ts"];
  const v1 = parts["v1"];
  if (!ts || !v1) return false;
  const manifest = `id:${dataId};request-id:${xRequestId};ts:${ts};`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(MP_WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(manifest));
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex === v1;
}

serve(async (req) => {
  try {
    const url = new URL(req.url);
    const raw = await req.text();
    let body: Record<string, unknown> = {};
    try {
      body = raw ? JSON.parse(raw) : {};
    } catch (_) {
      // MP a veces manda form-urlencoded; los datos clave van en la query.
    }

    // type/topic y data.id pueden venir por query o por body.
    const type = url.searchParams.get("type") ??
      url.searchParams.get("topic") ??
      (body["type"] as string | undefined) ??
      "";
    const dataId = url.searchParams.get("data.id") ??
      url.searchParams.get("id") ??
      ((body["data"] as Record<string, unknown> | undefined)?.["id"] as string | undefined) ??
      "";

    // Solo interesan las notificaciones de pago.
    if (type !== "payment" || !dataId) {
      return new Response("ignored", { status: 200 });
    }

    const ok = await validSignature(
      dataId,
      req.headers.get("x-signature") ?? "",
      req.headers.get("x-request-id") ?? "",
    );
    if (!ok) return new Response("invalid signature", { status: 401 });

    // Detalle del pago.
    const payRes = await fetch(`https://api.mercadopago.com/v1/payments/${dataId}`, {
      headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
    });
    if (!payRes.ok) return new Response("mp fetch error", { status: 502 });
    const pay = await payRes.json();

    const externalRef: string | null = pay["external_reference"] ?? null;
    const amount = Number(pay["transaction_amount"] ?? 0);
    const status: string = pay["status"] ?? "pending";
    const methodType: string | null = pay["payment_type_id"] ?? null;
    const dateApproved: string | null = pay["date_approved"] ?? null;
    const mpPaymentId = String(pay["id"] ?? dataId);

    // El external_reference es el id del cobro; de ahí sacamos el centro.
    let charge: Record<string, unknown> | null = null;
    if (externalRef) {
      const { data } = await supabase
        .from("charges")
        .select("*")
        .eq("id", externalRef)
        .maybeSingle();
      charge = data;
    }
    if (!charge) {
      // Sin cobro asociado no podemos atribuir el centro; se acepta (200) para
      // que MP no reintente indefinidamente, pero no se ingiere.
      return new Response("no matching charge", { status: 200 });
    }
    const orgId = charge["organization_id"] as string;
    const approved = status === "approved";

    // Idempotencia: no dupliques el mismo pago.
    const { data: existing } = await supabase
      .from("point_payments")
      .select("id")
      .eq("mp_payment_id", mpPaymentId)
      .maybeSingle();

    const nowIso = new Date().toISOString();
    const row = {
      organization_id: orgId,
      provider: "mercadopago",
      mp_payment_id: mpPaymentId,
      amount,
      currency: pay["currency_id"] ?? "MXN",
      status,
      method: methodType,
      external_reference: externalRef,
      description: pay["description"] ?? "Pago Mercado Pago",
      captured_at: dateApproved ?? nowIso,
      charge_id: approved ? (charge["id"] as string) : null,
      linked_at: approved ? nowIso : null,
      source: "webhook",
      raw: pay,
      updated_at: nowIso,
    };

    if (existing) {
      await supabase.from("point_payments").update(row).eq("id", existing.id);
    } else {
      await supabase.from("point_payments").insert({ ...row, created_at: nowIso });
    }

    // Si el pago está aprobado, marca el cobro como pagado por MP.
    if (approved && charge["status"] !== "pagado") {
      await supabase.from("charges").update({
        status: "pagado",
        payment_method: "tarjeta",
        payment_provider: "mercadopago",
        mp_payment_id: mpPaymentId,
        external_reference: externalRef,
        mp_status: status,
        paid_at: dateApproved ?? nowIso,
        updated_at: nowIso,
      }).eq("id", charge["id"] as string);
    }

    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("mercadopago-webhook error", e);
    return new Response("error", { status: 500 });
  }
});
