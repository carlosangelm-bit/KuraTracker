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
//   MP_MODE             — 'test' (por defecto) | 'prod'. Elige qué token usar.
//                         Fail-safe: si no se define, usa PRUEBA (nunca cobra
//                         real por descuido). En go-live: MP_MODE=prod.
//   MP_ACCESS_TOKEN     — token de PRODUCCIÓN (APP_USR-…).
//   MP_ACCESS_TOKEN_TEST— token de PRUEBA (TEST-…).
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
// Modo por defecto TEST (fail-safe): solo cobra real con MP_MODE=prod explícito.
const MP_MODE = (Deno.env.get("MP_MODE") ?? "test").toLowerCase();
const MP_ACCESS_TOKEN = (MP_MODE === "prod"
  ? Deno.env.get("MP_ACCESS_TOKEN")
  : Deno.env.get("MP_ACCESS_TOKEN_TEST")) ?? "";
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

    // Procesamos pagos (Checkout) y órdenes (Point / Orders API). El resto se
    // ignora respondiendo 200.
    if (type !== "payment" && type !== "order") return ok200("ignored");

    const valid = await validSignature(
      String(dataId),
      req.headers.get("x-signature") ?? "",
      req.headers.get("x-request-id") ?? "",
    );
    if (!valid) return new Response("invalid signature", { status: 401 });

    // Normaliza los datos del pago según el tipo de notificación.
    let externalRef: string | null = null;
    let amount = 0;
    let status = "pending";
    let methodType: string | null = null;
    let dateApproved: string | null = null;
    let mpPaymentId = String(dataId);
    let description = "Pago Mercado Pago";
    let raw: unknown = body;

    if (type === "order") {
      // Orders API (Point / nuevo modelo): el pago viene EMBEBIDO en el body,
      // sin necesidad de consultar /v1/payments.
      const d = (body["data"] as Record<string, unknown> | undefined) ?? {};
      externalRef = (d["external_reference"] as string | undefined) ?? null;
      const txs = d["transactions"] as Record<string, unknown> | undefined;
      const payments =
        (txs?.["payments"] as Array<Record<string, unknown>> | undefined) ?? [];
      const p0 = payments[0] ?? {};
      const st = (p0["status"] ?? d["status"] ?? "") as string;
      const detail = (p0["status_detail"] ?? d["status_detail"] ?? "") as string;
      status = (st === "approved" || st === "processed" || detail === "accredited")
        ? "approved"
        : (st || "pending");
      methodType = ((p0["payment_method"] as Record<string, unknown> | undefined)?.["type"] as
        string | undefined) ?? null;
      mpPaymentId = String(p0["id"] ?? d["id"] ?? dataId);
      description = "Pago Mercado Pago (Point)";
    } else {
      // type === "payment": consultar el pago en MP.
      const payRes = await fetch(`https://api.mercadopago.com/v1/payments/${dataId}`, {
        headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
      });
      if (!payRes.ok) {
        // id inexistente (p.ej. simulación) o error transitorio: 200 para no
        // marcar el endpoint como caído; "Verificar pago" (pull) cubre gaps.
        console.error("MP fetch payment no-ok", payRes.status, dataId);
        return ok200("payment fetch failed");
      }
      const pay = await payRes.json();
      externalRef = (pay["external_reference"] as string | undefined) ?? null;
      amount = Number(pay["transaction_amount"] ?? 0);
      status = (pay["status"] as string | undefined) ?? "pending";
      methodType = (pay["payment_type_id"] as string | undefined) ?? null;
      dateApproved = (pay["date_approved"] as string | undefined) ?? null;
      mpPaymentId = String(pay["id"] ?? dataId);
      description = (pay["description"] as string | undefined) ?? description;
      raw = pay;
    }

    if (!externalRef) return ok200("no external_reference");

    const { data: charge } = await supabase
      .from("charges").select("*").eq("id", externalRef).maybeSingle();
    if (!charge) return ok200("no matching charge");

    const orgId = charge["organization_id"] as string;
    const approved = status === "approved";
    // Para órdenes (Point) usamos el total del cobro como monto autoritativo.
    if (amount <= 0) amount = Number(charge["total"] ?? 0);

    const { data: existing } = await supabase
      .from("point_payments").select("id").eq("mp_payment_id", mpPaymentId).maybeSingle();

    const nowIso = new Date().toISOString();
    const rowData = {
      organization_id: orgId,
      provider: "mercadopago",
      mp_payment_id: mpPaymentId,
      amount,
      currency: "MXN",
      status,
      method: methodType,
      external_reference: externalRef,
      description,
      captured_at: dateApproved ?? nowIso,
      charge_id: approved ? (charge["id"] as string) : null,
      linked_at: approved ? nowIso : null,
      source: "webhook",
      raw,
      updated_at: nowIso,
    };
    if (existing) {
      await supabase.from("point_payments").update(rowData).eq("id", existing.id);
    } else {
      await supabase.from("point_payments").insert({ ...rowData, created_at: nowIso });
    }

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

    return ok200("ok");
  } catch (e) {
    console.error("mercadopago-webhook error", e);
    return ok200("error"); // 200 para no marcar el endpoint como caído.
  }
});

function ok200(msg: string) {
  return new Response(msg, { status: 200 });
}
