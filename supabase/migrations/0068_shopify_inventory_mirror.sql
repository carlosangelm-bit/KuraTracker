-- =============================================================================
-- 0068_shopify_inventory_mirror.sql — Inventario espejo con Shopify (Kura+)
-- =============================================================================
-- Kura+ (centro dueño de la tienda) mantiene su inventario como ESPEJO de
-- Shopify: se marca la organización con shopify_mirror = true. Para poder
-- escribir de vuelta en Shopify al consumir, cada artículo guarda el
-- inventory_item_id de Shopify. Los demás centros no usan esto (inventario
-- propio por CSV).
-- =============================================================================

alter table public.organizations
  add column if not exists shopify_mirror boolean not null default false;

alter table public.inventory_items
  add column if not exists shopify_inventory_item_id text;

comment on column public.organizations.shopify_mirror is
  'true = el inventario del centro es espejo de Shopify (Kura+, dueño de la tienda).';
comment on column public.inventory_items.shopify_inventory_item_id is
  'inventory_item_id de Shopify (gid) para ajustar existencias de vuelta en la tienda.';
