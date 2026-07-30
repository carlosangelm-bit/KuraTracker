// shopify-sync-catalog — Siembra/actualiza el catálogo GLOBAL de productos
// (product_catalog) desde la Admin GraphQL API de Shopify. Solo el master
// (Kura+, dueño de la tienda) puede dispararla; los centros cliente solo leen.
//
// NOTA: las apps nuevas del dev dashboard de Shopify ya NO exponen la REST
// Admin API (deprecada); se usa GraphQL con el token atkn_… en el header
// X-Shopify-Access-Token.
//
// Deploy: supabase functions deploy shopify-sync-catalog --use-api   (verify_jwt)
// Secrets: SHOPIFY_ADMIN_TOKEN, SHOPIFY_STORE_DOMAIN, SHOPIFY_API_VERSION (default 2025-01)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMIN_TOKEN = Deno.env.get("SHOPIFY_ADMIN_TOKEN") ?? "";
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

// gid://shopify/Product/123 -> "123"
function numId(gid: unknown): string {
  return String(gid ?? "").split("/").pop() ?? "";
}

const QUERY = `query($cursor: String) {
  products(first: 100, after: $cursor) {
    pageInfo { hasNextPage endCursor }
    edges { node {
      id title vendor productType
      featuredImage { url }
      variants(first: 100) { edges { node { id sku title price } } }
    } }
  }
}`;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "No autenticado." }, 401);
  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller.user) return json({ error: "Sesión inválida." }, 401);
  const { data: profile } = await admin
    .from("profiles").select("role").eq("id", caller.user.id).maybeSingle();
  if (profile?.role !== "master") {
    return json({ error: "Solo el master puede sincronizar el catálogo." }, 403);
  }

  if (!ADMIN_TOKEN || !STORE_DOMAIN) {
    return json(
      { error: "Falta configurar SHOPIFY_ADMIN_TOKEN / SHOPIFY_STORE_DOMAIN." },
      500,
    );
  }

  const endpoint = `https://${STORE_DOMAIN}/admin/api/${API_VERSION}/graphql.json`;
  let cursor: string | null = null;
  let upserted = 0;
  const seen = new Set<string>();
  // Los tokens clásicos (shpat_) usan X-Shopify-Access-Token; algunos tokens
  // nuevos van como Authorization: Bearer. Se prueban ambos.
  let useBearer = false;

  async function gql(c: string | null) {
    const headers: Record<string, string> = { "content-type": "application/json" };
    if (useBearer) {
      headers["Authorization"] = `Bearer ${ADMIN_TOKEN}`;
    } else {
      headers["X-Shopify-Access-Token"] = ADMIN_TOKEN;
    }
    const r = await fetch(endpoint, {
      method: "POST",
      headers,
      body: JSON.stringify({ query: QUERY, variables: { cursor: c } }),
    });
    // deno-lint-ignore no-explicit-any
    const b: any = await r.json().catch(() => ({}));
    return { r, b };
  }

  try {
    while (true) {
      let { r: res, b: body } = await gql(cursor);
      // Si el primer intento con X-Shopify-Access-Token es 401, reintenta Bearer.
      if ((res.status === 401 || body?.errors) && !useBearer) {
        useBearer = true;
        ({ r: res, b: body } = await gql(cursor));
      }
      if (!res.ok || body?.errors) {
        console.error("shopify graphql error", res.status, JSON.stringify(body));
        return json(
          {
            error:
                `Shopify GraphQL HTTP ${res.status} en ${endpoint}. `
                + `Detalle: ${JSON.stringify(body?.errors ?? body).slice(0, 300)}`,
            hint: res.status === 401 || res.status === 403
                ? 'Token inválido o app no instalada en la tienda.'
                : 'Revisa que el scope read_products esté aprobado en la app.',
          },
          502,
        );
      }

      const conn = body?.data?.products;
      const edges = (conn?.edges ?? []) as Array<Record<string, unknown>>;
      const rows: Array<Record<string, unknown>> = [];
      const now = new Date().toISOString();
      for (const e of edges) {
        const p = (e["node"] ?? {}) as Record<string, unknown>;
        const pid = numId(p["id"]);
        const img = (p["featuredImage"] as Record<string, unknown> | null)?.["url"] ?? null;
        const vEdges = ((p["variants"] as Record<string, unknown>)?.["edges"] ?? []) as
          Array<Record<string, unknown>>;
        for (const ve of vEdges) {
          const v = (ve["node"] ?? {}) as Record<string, unknown>;
          const vid = numId(v["id"]);
          seen.add(`${pid}|${vid}`);
          rows.push({
            shopify_product_id: pid,
            shopify_variant_id: vid,
            sku: (v["sku"] as string) ?? null,
            title: (p["title"] as string) ?? "Producto",
            variant_title: (v["title"] as string) ?? null,
            vendor: (p["vendor"] as string) ?? null,
            product_type: (p["productType"] as string) ?? null,
            price: v["price"] != null ? Number(v["price"]) : null,
            currency: "MXN",
            image_url: img,
            is_active: true,
            updated_at: now,
          });
        }
      }
      if (rows.length > 0) {
        const { error: upErr } = await admin
          .from("product_catalog")
          .upsert(rows, { onConflict: "shopify_product_id,shopify_variant_id" });
        if (upErr) {
          console.error("upsert catalog error", upErr);
          return json({ error: `No se pudo guardar el catálogo: ${upErr.message}` }, 500);
        }
        upserted += rows.length;
      }

      if (conn?.pageInfo?.hasNextPage !== true) break;
      cursor = conn.pageInfo.endCursor as string;
    }

    return json({ ok: true, upserted, distinct: seen.size });
  } catch (e) {
    console.error("shopify-sync-catalog error", e);
    return json({ error: "Error al sincronizar el catálogo." }, 502);
  }
});
