-- =============================================================================
-- 0143_protocol_catalog_orphans_scope.sql — Matriz del protocolo · ETAPA 6.2 (fuga transversal)
-- =============================================================================
-- resolve_protocol_orphans es SECURITY DEFINER: la RLS de inventory_items NO aplica dentro. La
-- AUTORIDAD (current_user_can_author_catalog) se evalúa sobre current_organization_id() —el centro
-- EN SESIÓN—, pero el join de inventario usaba p_organization_id sin validarlo. Un admin de Kura+
-- podía pasar el id de OTRO centro y deducir, por los motivos de huérfana, qué productos del
-- catálogo tiene ESE centro en inventario. Fuga transversal.
--
-- Se ancla p_organization_id al centro en sesión (salvo master, que legítimamente consulta
-- cualquiera). Un no-master que pase otro id → 0 filas, sin fuga.
-- =============================================================================

create or replace function public.resolve_protocol_orphans(
  p_organization_id uuid,
  p_site_id uuid default null
)
returns table (rule_id uuid, category text, inventory_item_id uuid, reason text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.id, r.category, null::uuid,
         case when r.shopify_product_id is null then 'sin identidad de producto'
              else 'el insumo no está en este '
                   || case when p_site_id is null then 'centro' else 'sitio' end
         end
  from public.protocol_catalog_rules r
  where public.current_user_can_author_catalog()   -- autoridad única (rol + derecho, o master)
    -- ANCLA anti-fuga: SECURITY DEFINER salta la RLS de inventory_items, así que el centro
    -- consultado DEBE ser el de la sesión (el master puede cualquiera). Sin esto, un author
    -- deduce el inventario de otro centro por los motivos de huérfana.
    and (public.is_master() or p_organization_id = public.current_organization_id())
    and (
      r.shopify_product_id is null
      or not exists (
        select 1 from public.inventory_items i
        where i.organization_id = p_organization_id
          and i.shopify_product_id = r.shopify_product_id
          and coalesce(i.shopify_variant_id, '') = coalesce(r.shopify_variant_id, '')
          and (p_site_id is null or i.site_id = p_site_id)
      )
    );
$$;
comment on function public.resolve_protocol_orphans(uuid, uuid) is
  'Reglas del CATÁLOGO Kura+ que no aterrizan en el inventario del centro EN SESIÓN. Autoridad: '
  'current_user_can_author_catalog (rol admin + protocol:author, o master). SECURITY DEFINER, así '
  'que p_organization_id se ancla a current_organization_id() salvo master (anti-fuga transversal).';
