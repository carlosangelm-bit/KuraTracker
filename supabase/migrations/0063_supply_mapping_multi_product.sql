-- =============================================================================
-- 0063_supply_mapping_multi_product.sql — Varios productos por insumo genérico
-- =============================================================================
-- Antes: un insumo genérico (método + producto genérico) se ligaba a UN solo
-- producto de la tienda (unique organization_id, method, generic_product).
-- Ahora un mismo insumo genérico puede ligarse a VARIOS productos (distintas
-- medidas, marcas y SKU) para que el especialista elija el específico al usarlo.
--
-- Se elimina el unique por (org, método, genérico) y se agrega un unique por
-- producto/variante concreto, para no permitir duplicar exactamente el mismo
-- producto+presentación en el mismo insumo genérico. La variante nula se
-- normaliza a '' para que el unique la considere.
-- =============================================================================

-- 1. Quitar el unique viejo (nombre autogenerado; se elimina cualquier unique
--    de la tabla de forma robusta, sin depender del nombre exacto/truncado).
do $$
declare
  c record;
begin
  for c in
    select conname
      from pg_constraint
     where conrelid = 'public.supply_product_mappings'::regclass
       and contype = 'u'
  loop
    execute format(
      'alter table public.supply_product_mappings drop constraint %I', c.conname);
  end loop;
end $$;

-- 2. Unique por producto/variante concreto dentro del insumo genérico.
create unique index if not exists supply_product_mappings_unique_product
  on public.supply_product_mappings (
    organization_id,
    method,
    generic_product,
    shopify_product_id,
    coalesce(shopify_variant_id, '')
  );
