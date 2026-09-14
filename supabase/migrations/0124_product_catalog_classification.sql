-- =============================================================================
-- 0124_product_catalog_classification.sql
-- =============================================================================
-- §3 del catálogo de insumos clasificado. product_catalog (0067) es la única
-- tabla GLOBAL del modelo de insumos, y solo trae los campos de Shopify
-- (product_type, vendor). No tiene clasificación clínica. Se agregan dos columnas
-- para poder sembrar el mapeo protocolo→producto (§4):
--   - kura_tag: el PASO del protocolo (KuraTag.dbValue).
--   - generic_product: la clave del insumo GENÉRICO al que corresponde (el mismo
--     literal de TreatmentCatalog.methodToProducts, carácter por carácter).
--
-- REQUISITO CRÍTICO (preservación): el upsert de shopify-sync-catalog es por
-- (shopify_product_id, shopify_variant_id) y NO incluye estas columnas en su
-- payload, así que un re-sync NO las pisa (PostgREST solo actualiza las columnas
-- enviadas; las ausentes se conservan). Aditivas y nullable: los productos sin
-- clasificar quedan en NULL. Ver la nota en supabase/functions/shopify-sync-catalog.
-- =============================================================================

alter table public.product_catalog
  add column if not exists kura_tag text,
  add column if not exists generic_product text;

comment on column public.product_catalog.kura_tag is
  'Clasificación clínica (§3): paso del protocolo = KuraTag.dbValue. NULL = sin clasificar. shopify-sync-catalog NO la toca (se preserva en cada re-sync).';
comment on column public.product_catalog.generic_product is
  'Clasificación clínica (§3): clave del insumo genérico (literal de TreatmentCatalog.methodToProducts). NULL = sin clasificar. Preservada en el re-sync.';

-- Índice para sembrar/consultar por paso (los productos clasificados son pocos).
create index if not exists idx_product_catalog_kura_tag
  on public.product_catalog(kura_tag)
  where kura_tag is not null;
