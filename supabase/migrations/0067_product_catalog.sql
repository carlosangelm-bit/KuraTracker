-- =============================================================================
-- 0067_product_catalog.sql — Catálogo GLOBAL de productos (sembrado de Shopify)
-- =============================================================================
-- Catálogo compartido de todos los insumos disponibles en la tienda de Kura+.
-- Lo siembra la Edge Function shopify-sync-catalog (Admin API) y lo LEEN todos
-- los centros — incluso los que no están conectados a Shopify — para poder
-- descargar el CSV de carga masiva de inventario y saber qué hay disponible.
--
-- Escritura: solo el servicio (Edge Function con service_role); no hay policy
-- de escritura para clientes. Lectura: cualquier usuario autenticado (global).
-- =============================================================================

create table if not exists public.product_catalog (
  id uuid primary key default gen_random_uuid(),
  shopify_product_id text not null,
  shopify_variant_id text not null default '',
  sku text,
  title text not null,
  variant_title text,
  vendor text,
  product_type text,
  price numeric(10, 2),
  currency text,
  image_url text,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (shopify_product_id, shopify_variant_id)
);

create index if not exists idx_product_catalog_active
  on public.product_catalog(is_active);

alter table public.product_catalog enable row level security;

-- Lectura global: cualquier usuario autenticado (catálogo compartido entre
-- centros). Sin policies de escritura → los clientes no pueden modificarlo;
-- la Edge Function lo siembra con service_role (bypassa RLS).
drop policy if exists product_catalog_select on public.product_catalog;
create policy product_catalog_select on public.product_catalog
  for select using (auth.uid() is not null);
