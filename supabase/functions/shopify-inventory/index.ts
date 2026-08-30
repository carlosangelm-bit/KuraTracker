// shopify-inventory — Espejo de existencias Kura+ ↔ Shopify (Admin GraphQL).
//   action "levels": devuelve las existencias por variante (para reflejar
//                     Shopify → KuraTracker). La reconciliación la hace la app.
//   action "adjust": ajusta una existencia en Shopify (KuraTracker → Shopify)
//                     al consumir/reponer.
//
// Solo usuarios de un centro con shopify_mirror = true. Token vía
// client_credentials (SHOPIFY_CLIENT_ID/SECRET) o SHOPIFY_ADMIN_TOKEN.
//
// Deploy: supabase functions deploy shopify-inventory --use-api  (verify_jwt)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMIN_TOKEN = Deno.env.get("SHOPIFY_ADMIN_TOKEN") ?? "";
const CLIENT_ID = Deno.env.get("SHOPIFY_CLIENT_ID") ?? "";
const CLIENT_SECRET = Deno.env.get("SHOPIFY_CLIENT_SECRET") ?? "";
const STORE_DOMAIN = Deno.env.get("SHOPIFY_STORE_DOMAIN") ?? "";
const API_VERSION = Deno.env.get("SHOPIFY_API_VERSION") ?? "2025-01";

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
const numId = (gid: unknown) => String(gid ?? "").split("/").pop() ?? "";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "No autenticado." }, 401);
  // Llamada de SERVICIO (webhooks de pago con SERVICE_ROLE): confiable, sin
  // usuario. Solo `reconcile_charge` la usa, y ahí el espejo se deriva del
  // COBRO, no del llamador. Las demás acciones siguen exigiendo un usuario de
  // un centro espejo (Kura+).
  const isService = jwt === SERVICE_ROLE;
  let orgId: string | undefined;
  if (!isService) {
    const { data: caller, error: cErr } = await admin.auth.getUser(jwt);
    if (cErr || !caller.user) return json({ error: "Sesión inválida." }, 401);
    const { data: prof } = await admin
      .from("profiles").select("organization_id, role").eq("id", caller.user.id).maybeSingle();
    orgId = prof?.organization_id as string | undefined;
    let mirror = false;
    if (orgId) {
      const { data: org } = await admin
        .from("organizations").select("shopify_mirror").eq("id", orgId).maybeSingle();
      mirror = org?.shopify_mirror === true;
    }
    if (!mirror && prof?.role !== "master") {
      return json({ error: "El espejo de inventario solo aplica al centro Kura+." }, 403);
    }
  }

  if (!STORE_DOMAIN || (!(CLIENT_ID && CLIENT_SECRET) && !ADMIN_TOKEN)) {
    return json({ error: "Faltan credenciales de Shopify." }, 500);
  }

  // Token de acceso (client_credentials si hay id/secret; si no, estático).
  let accessToken = ADMIN_TOKEN;
  if (CLIENT_ID && CLIENT_SECRET) {
    const t = await fetch(`https://${STORE_DOMAIN}/admin/oauth/access_token`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET,
      }).toString(),
    });
    const tb = await t.json().catch(() => ({}));
    if (!t.ok || !tb?.access_token) {
      return json({ error: `No se pudo obtener token (HTTP ${t.status}).` }, 502);
    }
    accessToken = tb.access_token;
  }

  const endpoint = `https://${STORE_DOMAIN}/admin/api/${API_VERSION}/graphql.json`;
  async function gql(query: string, variables: Record<string, unknown>) {
    const r = await fetch(endpoint, {
      method: "POST",
      headers: {
        "X-Shopify-Access-Token": accessToken,
        "content-type": "application/json",
      },
      body: JSON.stringify({ query, variables }),
    });
    // deno-lint-ignore no-explicit-any
    const b: any = await r.json().catch(() => ({}));
    return { r, b };
  }

  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch (_) {
    return json({ error: "Body inválido." }, 400);
  }
  const action = payload["action"] as string | undefined;

  try {
    if (action === "levels") {
      const QUERY = `query($cursor:String){
        productVariants(first:100, after:$cursor){
          pageInfo{ hasNextPage endCursor }
          edges{ node{ id inventoryQuantity product{ id } inventoryItem{ id } } }
        }
      }`;
      const out: Array<Record<string, unknown>> = [];
      let cursor: string | null = null;
      while (true) {
        const { r, b } = await gql(QUERY, { cursor });
        if (!r.ok || b?.errors) {
          return json({ error: `Shopify GraphQL HTTP ${r.status}: ${JSON.stringify(b?.errors ?? b).slice(0, 300)}` }, 502);
        }
        const conn = b?.data?.productVariants;
        for (const e of (conn?.edges ?? [])) {
          const n = e.node;
          out.push({
            productId: numId(n?.product?.id),
            variantId: numId(n?.id),
            inventoryItemId: n?.inventoryItem?.id ?? null, // gid completo (para adjust)
            available: Number(n?.inventoryQuantity ?? 0),
          });
        }
        if (conn?.pageInfo?.hasNextPage !== true) break;
        cursor = conn.pageInfo.endCursor;
      }
      return json({ ok: true, levels: out });
    }

    if (action === "adjust") {
      const inventoryItemId = payload["inventoryItemId"] as string | undefined;
      const delta = Number(payload["delta"] ?? 0);
      if (!inventoryItemId || !delta) {
        return json({ error: "Faltan inventoryItemId o delta." }, 400);
      }
      // Ubicación activa (primera).
      const locRes = await gql(
        `{ locations(first:5){ edges{ node{ id isActive } } } }`, {});
      if (!locRes.r.ok || locRes.b?.errors) {
        return json({ error: `No se pudo leer ubicaciones (HTTP ${locRes.r.status}).` }, 502);
      }
      const locs = (locRes.b?.data?.locations?.edges ?? []) as Array<Record<string, unknown>>;
      const active = locs.find((e) => (e.node as Record<string, unknown>)?.isActive === true) ?? locs[0];
      const locationId = (active?.node as Record<string, unknown>)?.id as string | undefined;
      if (!locationId) return json({ error: "Sin ubicación en Shopify." }, 502);

      const M = `mutation($input: InventoryAdjustQuantitiesInput!){
        inventoryAdjustQuantities(input:$input){ userErrors{ field message } }
      }`;
      const input = {
        name: "available",
        reason: "correction",
        changes: [{ delta, inventoryItemId, locationId }],
      };
      const { r, b } = await gql(M, { input });
      const errs = b?.data?.inventoryAdjustQuantities?.userErrors ?? [];
      if (!r.ok || b?.errors || errs.length > 0) {
        return json({ error: `Ajuste rechazado: ${JSON.stringify(b?.errors ?? errs).slice(0, 300)}` }, 502);
      }
      return json({ ok: true });
    }

    if (action === "reconcile_charge") {
      // Empuja a Shopify el consumo de un cobro (movimientos del trigger 0091)
      // para que la próxima sync no revierta el descuento. Idempotente por
      // `shopify_pushed`. La disparan app y webhooks tras pagar (best-effort).
      const chargeId = payload["chargeId"] as string | undefined;
      if (!chargeId) return json({ error: "Falta chargeId." }, 400);

      const { data: charge } = await admin
        .from("charges").select("organization_id").eq("id", chargeId).maybeSingle();
      const cOrg = (charge as Record<string, unknown> | null)?.organization_id as string | undefined;
      if (!cOrg) return json({ ok: true, pushed: 0, skipped: "cobro no encontrado" });
      const { data: org } = await admin
        .from("organizations").select("shopify_mirror").eq("id", cOrg).maybeSingle();
      if ((org as Record<string, unknown> | null)?.shopify_mirror !== true) {
        return json({ ok: true, pushed: 0, skipped: "centro sin espejo" });
      }
      if (!isService && orgId !== cOrg) {
        return json({ error: "El cobro es de otro centro." }, 403);
      }

      // Movimientos de consumo del cobro, aún no empujados, con item ligado.
      const { data: moves } = await admin
        .from("inventory_movements")
        .select("id, delta, inventory_items!inner(shopify_inventory_item_id)")
        .eq("charge_id", chargeId)
        .eq("reason", "consumo")
        .eq("shopify_pushed", false);
      // deno-lint-ignore no-explicit-any
      const rows = ((moves ?? []) as Array<any>).filter((m) =>
        m.inventory_items?.shopify_inventory_item_id
      );
      if (rows.length === 0) return json({ ok: true, pushed: 0 });

      // Ubicación activa (una vez para todo el cobro).
      const locRes = await gql(`{ locations(first:5){ edges{ node{ id isActive } } } }`, {});
      if (!locRes.r.ok || locRes.b?.errors) {
        return json({ error: `No se pudo leer ubicaciones (HTTP ${locRes.r.status}).` }, 502);
      }
      const locs = (locRes.b?.data?.locations?.edges ?? []) as Array<Record<string, unknown>>;
      const active = locs.find((e) => (e.node as Record<string, unknown>)?.isActive === true) ?? locs[0];
      const locationId = (active?.node as Record<string, unknown>)?.id as string | undefined;
      if (!locationId) return json({ error: "Sin ubicación en Shopify." }, 502);

      const M = `mutation($input: InventoryAdjustQuantitiesInput!){
        inventoryAdjustQuantities(input:$input){ userErrors{ field message } }
      }`;
      const pushedIds: string[] = [];
      async function markPushed() {
        if (pushedIds.length) {
          await admin.from("inventory_movements")
            .update({ shopify_pushed: true }).in("id", pushedIds);
        }
      }
      for (const m of rows) {
        const input = {
          name: "available",
          reason: "correction",
          changes: [{
            delta: Number(m.delta),
            inventoryItemId: m.inventory_items.shopify_inventory_item_id,
            locationId,
          }],
        };
        const { r, b } = await gql(M, { input });
        const errs = b?.data?.inventoryAdjustQuantities?.userErrors ?? [];
        if (!r.ok || b?.errors || errs.length > 0) {
          // Best-effort: marca lo ya empujado (idempotencia) y reporta; el resto
          // sigue shopify_pushed=false y se reintenta en la próxima llamada.
          await markPushed();
          return json({
            error: `Ajuste rechazado: ${JSON.stringify(b?.errors ?? errs).slice(0, 300)}`,
            pushed: pushedIds.length,
          }, 502);
        }
        pushedIds.push(m.id as string);
      }
      await markPushed();
      return json({ ok: true, pushed: pushedIds.length });
    }

    if (action === "reconcile_pending") {
      // Barre los movimientos de consumo del centro aún NO empujados a Shopify y
      // los empuja (idempotente por shopify_pushed). Se llama al INICIO de la
      // sincronización, ANTES de calcular deltas, para que la sync no revierta
      // un descuento que reconcile_charge no alcanzó a reflejar. Solo aplica a
      // centros espejo (el gate de usuario ya lo verificó).
      const targetOrg = isService
        ? (payload["organizationId"] as string | undefined)
        : orgId;
      if (!targetOrg) return json({ ok: true, pushed: 0 });

      const { data: moves } = await admin
        .from("inventory_movements")
        .select("id, delta, inventory_items!inner(shopify_inventory_item_id)")
        .eq("organization_id", targetOrg)
        .eq("reason", "consumo")
        .eq("shopify_pushed", false)
        .limit(200);
      // deno-lint-ignore no-explicit-any
      const rows = ((moves ?? []) as Array<any>).filter((m) =>
        m.inventory_items?.shopify_inventory_item_id
      );
      if (rows.length === 0) return json({ ok: true, pushed: 0 });

      const locRes = await gql(
        `{ locations(first:5){ edges{ node{ id isActive } } } }`, {});
      if (!locRes.r.ok || locRes.b?.errors) {
        return json({ error: `No se pudo leer ubicaciones (HTTP ${locRes.r.status}).` }, 502);
      }
      const locs = (locRes.b?.data?.locations?.edges ?? []) as Array<Record<string, unknown>>;
      const active = locs.find((e) => (e.node as Record<string, unknown>)?.isActive === true) ?? locs[0];
      const locationId = (active?.node as Record<string, unknown>)?.id as string | undefined;
      if (!locationId) return json({ error: "Sin ubicación en Shopify." }, 502);

      const M = `mutation($input: InventoryAdjustQuantitiesInput!){
        inventoryAdjustQuantities(input:$input){ userErrors{ field message } }
      }`;
      const pushedIds: string[] = [];
      async function markPending() {
        if (pushedIds.length) {
          await admin.from("inventory_movements")
            .update({ shopify_pushed: true }).in("id", pushedIds);
        }
      }
      for (const m of rows) {
        const input = {
          name: "available",
          reason: "correction",
          changes: [{
            delta: Number(m.delta),
            inventoryItemId: m.inventory_items.shopify_inventory_item_id,
            locationId,
          }],
        };
        const { r, b } = await gql(M, { input });
        const errs = b?.data?.inventoryAdjustQuantities?.userErrors ?? [];
        if (!r.ok || b?.errors || errs.length > 0) {
          await markPending();
          return json({
            error: `Ajuste rechazado: ${JSON.stringify(b?.errors ?? errs).slice(0, 300)}`,
            pushed: pushedIds.length,
          }, 502);
        }
        pushedIds.push(m.id as string);
      }
      await markPending();
      return json({ ok: true, pushed: pushedIds.length });
    }

    return json({ error: "Acción no soportada." }, 400);
  } catch (e) {
    console.error("shopify-inventory error", e);
    return json({ error: "Error en el espejo de inventario." }, 502);
  }
});
