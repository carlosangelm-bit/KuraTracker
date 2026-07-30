// shopify-sync-catalog — Siembra/actualiza el catálogo GLOBAL de productos
// (product_catalog) desde la Admin API de Shopify. Solo el master (Kura+, dueño
// de la tienda) puede dispararla. Los centros cliente solo LEEN el catálogo.
//
// Deploy: supabase functions deploy shopify-sync-catalog --use-api   (verify_jwt)
// Secrets (Supabase):
//   SHOPIFY_ADMIN_TOKEN   -> token de automatización / Admin API (shpat_… o similar)
//   SHOPIFY_STORE_DOMAIN  -> dominio interno de la tienda (algo.myshopify.com)
//   SHOPIFY_API_VERSION   -> versión de la Admin API (default 2025-01)

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

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Autenticación + autorización: solo master.
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

  const base = `https://${STORE_DOMAIN}/admin/api/${API_VERSION}`;
  let url: string | null = `${base}/products.json?limit=250`;
  let upserted = 0;
  const seen = new Set<string>();

  try {
    while (url) {
      const res = await fetch(url, {
        headers: {
          "X-Shopify-Access-Token": ADMIN_TOKEN,
          "content-type": "application/json",
        },
      });
      if (!res.ok) {
        const txt = await res.text().catch(() => "");
        console.error("shopify products error", res.status, txt);
        return json(
          { error: `Shopify rechazó la lectura de productos (HTTP ${res.status}). Revisa el token y los scopes read_products.` },
          502,
        );
      }
      const body = await res.json();
      const products = (body?.products ?? []) as Array<Record<string, unknown>>;
      const rows: Array<Record<string, unknown>> = [];
      const now = new Date().toISOString();
      for (const p of products) {
        const vendor = (p["vendor"] as string) ?? null;
        const productType = (p["product_type"] as string) ?? null;
        const images = (p["images"] as Array<Record<string, unknown>>) ?? [];
        const image = images.length > 0 ? (images[0]["src"] as string) : null;
        const variants = (p["variants"] as Array<Record<string, unknown>>) ?? [];
        for (const v of variants) {
          const pid = String(p["id"]);
          const vid = String(v["id"] ?? "");
          seen.add(`${pid}|${vid}`);
          rows.push({
            shopify_product_id: pid,
            shopify_variant_id: vid,
            sku: (v["sku"] as string) ?? null,
            title: (p["title"] as string) ?? "Producto",
            variant_title: (v["title"] as string) ?? null,
            vendor,
            product_type: productType,
            price: v["price"] != null ? Number(v["price"]) : null,
            currency: "MXN",
            image_url: image,
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

      // Paginación por Link header (rel="next").
      const link = res.headers.get("link") ?? res.headers.get("Link") ?? "";
      const m = link.match(/<([^>]+)>;\s*rel="next"/);
      url = m ? m[1] : null;
    }

    return json({ ok: true, upserted, distinct: seen.size });
  } catch (e) {
    console.error("shopify-sync-catalog error", e);
    return json({ error: "Error al sincronizar el catálogo." }, 502);
  }
});
