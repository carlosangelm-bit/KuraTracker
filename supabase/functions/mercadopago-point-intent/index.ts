// mercadopago-point-intent — PUSH a la terminal Mercado Pago Point.
//
// Crea/cancela un "payment intent" en la terminal FÍSICA (Point Integration
// API) para cobrar presencialmente: la terminal pide la tarjeta y, al aprobar,
// Mercado Pago dispara el webhook / lo concilia el pull (external_reference =
// charges.id → se liga y marca el cobro como pagado, mismo pipeline que 0055).
//
// La app la invoca con el JWT del usuario. El Access Token de MP vive solo aquí.
//
// Deploy: supabase functions deploy mercadopago-point-intent  (verify_jwt)
// Secrets (Supabase):
//   MP_MODE              — 'test' (por defecto) | 'prod'. Fail-safe a prueba.
//   MP_ACCESS_TOKEN      — token de PRODUCCIÓN (APP_USR-…).
//   MP_ACCESS_TOKEN_TEST — token de PRUEBA (TEST-…).
//
// Acciones (body { action, ... }):
//   list_devices                         → lista las terminales de la cuenta.
//   set_pdv    { deviceId }              → pone la terminal en modo integrado.
//   create     { chargeId, deviceId? }   → envía la orden a la terminal.
//   cancel     { chargeId?, deviceId?, intentId? } → cancela la orden abierta.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_MODE = (Deno.env.get("MP_MODE") ?? "test").toLowerCase();
const MP_ACCESS_TOKEN = (MP_MODE === "prod"
  ? Deno.env.get("MP_ACCESS_TOKEN")
  : Deno.env.get("MP_ACCESS_TOKEN_TEST")) ?? "";

const POINT_API = "https://api.mercadopago.com/point/integration-api";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

// Propaga la razón real de MP para diagnosticar sin acceso a logs.
function mpError(prefix: string, status: number, mp: Record<string, unknown>) {
  const base = (mp?.message ?? mp?.error ?? `HTTP ${status}`) as string;
  const cause = Array.isArray(mp?.cause) && mp.cause.length
    ? " · " + mp.cause.map((c: Record<string, unknown>) =>
        c.description ?? c.code).join("; ")
    : "";
  return json({ error: `${prefix}: ${base}${cause}`, status, detail: mp }, 502);
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
  if (!MP_ACCESS_TOKEN) {
    return json({ error: "MP no configurado (falta MP_ACCESS_TOKEN)." }, 500);
  }

  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch (_) {
    return json({ error: "Body inválido." }, 400);
  }
  const action = (payload["action"] as string | undefined) ?? "create";
  const authHeader = { Authorization: `Bearer ${MP_ACCESS_TOKEN}` };

  // ---- list_devices: terminales asociadas a la cuenta ---------------------
  if (action === "list_devices") {
    const res = await fetch(`${POINT_API}/devices`, { headers: authHeader });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) return mpError("MP (list_devices)", res.status, data);
    return json({ devices: data?.devices ?? [], mode: MP_MODE });
  }

  // ---- set_pdv: pone la terminal en modo integrado (PDV) ------------------
  if (action === "set_pdv") {
    const deviceId = payload["deviceId"] as string | undefined;
    if (!deviceId) return json({ error: "Falta deviceId." }, 400);
    const res = await fetch(`${POINT_API}/devices/${deviceId}`, {
      method: "PATCH",
      headers: { ...authHeader, "content-type": "application/json" },
      body: JSON.stringify({ operating_mode: "PDV" }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) return mpError("MP (set_pdv)", res.status, data);
    return json({ ok: true, device: data });
  }

  // ---- create: envía la orden a la terminal -------------------------------
  if (action === "create") {
    const chargeId = payload["chargeId"] as string | undefined;
    if (!chargeId) return json({ error: "Falta chargeId." }, 400);

    const { data: charge } = await admin
      .from("charges").select("*").eq("id", chargeId).maybeSingle();
    if (!charge) return json({ error: "Cobro no encontrado." }, 404);
    if (charge["status"] === "pagado") {
      return json({ error: "El cobro ya está pagado." }, 409);
    }
    const total = Number(charge["total"] ?? 0);
    if (total <= 0) return json({ error: "Monto inválido." }, 400);

    // Terminal: la del body, o la configurada en el centro (0074).
    const orgId = charge["organization_id"] as string;
    let deviceId = payload["deviceId"] as string | undefined;
    if (!deviceId) {
      const { data: org } = await admin
        .from("organizations").select("mp_point_device_id").eq("id", orgId)
        .maybeSingle();
      deviceId = (org?.["mp_point_device_id"] as string | undefined) ?? undefined;
    }
    if (!deviceId) {
      return json({
        error: "Este centro no tiene terminal Point configurada. "
          + "Configúrala en Comercial → Terminal.",
      }, 400);
    }

    // El intent DEBE llevar el amount en CENTAVOS (entero).
    const amountCents = Math.round(total * 100);
    const intentBody = {
      amount: amountCents,
      additional_info: {
        external_reference: chargeId, // liga el pago al cobro (pipeline 0055)
        print_on_terminal: true,
      },
    };
    const res = await fetch(
      `${POINT_API}/devices/${deviceId}/payment-intents`,
      {
        method: "POST",
        headers: { ...authHeader, "content-type": "application/json" },
        body: JSON.stringify(intentBody),
      },
    );
    const intent = await res.json().catch(() => ({}));
    if (!res.ok) return mpError("MP (create intent)", res.status, intent);

    const nowIso = new Date().toISOString();
    const intentId = String(intent["id"] ?? "");

    // Registra en la bandeja (estado en_terminal: aún no cobrado).
    await admin.from("point_payments").insert({
      organization_id: orgId,
      provider: "mercadopago_point",
      mp_intent_id: intentId,
      amount: total,
      currency: "MXN",
      status: "on_terminal",
      external_reference: chargeId,
      device_id: deviceId,
      description: (payload["title"] as string | undefined)
        ?? "Cobro con terminal Point",
      charge_id: null,
      source: "point_intent",
      raw: intent,
      created_at: nowIso,
      updated_at: nowIso,
    });

    await admin.from("charges").update({
      payment_provider: "mercadopago",
      external_reference: chargeId,
      mp_status: "on_terminal",
      updated_at: nowIso,
    }).eq("id", chargeId);

    return json({
      intent_id: intentId,
      state: intent["state"] ?? "OPEN",
      device_id: deviceId,
    });
  }

  // ---- cancel: cancela la orden abierta en la terminal --------------------
  if (action === "cancel") {
    const chargeId = payload["chargeId"] as string | undefined;
    let deviceId = payload["deviceId"] as string | undefined;
    let intentId = payload["intentId"] as string | undefined;

    // Si no vienen, resuélvelos desde la última orden del cobro.
    if ((!deviceId || !intentId) && chargeId) {
      const { data: pp } = await admin
        .from("point_payments")
        .select("id, device_id, mp_intent_id")
        .eq("external_reference", chargeId)
        .eq("status", "on_terminal")
        .order("created_at", { ascending: false })
        .limit(1).maybeSingle();
      deviceId = deviceId ?? (pp?.["device_id"] as string | undefined);
      intentId = intentId ?? (pp?.["mp_intent_id"] as string | undefined);
    }
    if (!deviceId || !intentId) {
      return json({ error: "No hay orden abierta que cancelar." }, 404);
    }

    const res = await fetch(
      `${POINT_API}/devices/${deviceId}/payment-intents/${intentId}`,
      { method: "DELETE", headers: authHeader },
    );
    // MP responde 200/204 al cancelar; algunos estados ya cerrados dan 409.
    if (!res.ok && res.status !== 409) {
      const data = await res.json().catch(() => ({}));
      return mpError("MP (cancel intent)", res.status, data);
    }

    const nowIso = new Date().toISOString();
    await admin.from("point_payments")
      .update({ status: "canceled", updated_at: nowIso })
      .eq("mp_intent_id", intentId);
    if (chargeId) {
      await admin.from("charges")
        .update({ mp_status: "canceled", updated_at: nowIso })
        .eq("id", chargeId).eq("mp_status", "on_terminal");
    }
    return json({ ok: true });
  }

  return json({ error: `Acción no soportada: ${action}` }, 400);
});
