-- =============================================================================
-- 0142_protocol_catalog_authority.sql — Matriz del protocolo · ETAPA 6.2 (autoridad única)
-- =============================================================================
-- "¿Quién puede ver/editar el catálogo Kura+?" tenía TRES respuestas en tres capas:
--   · RLS protocol_catalog_rules_all (0137): is_master() OR (is_admin() AND author)  ← la real
--   · resolve_protocol_orphans (0140):       current_org_has_protocol_author()       ← SIN rol
--   · Dart isProtocolCatalogAuthor:          canWriteModule (derecho, SIN rol)        ← capacidad
-- Para un miembro de Kura+ SIN rol admin: el cliente abre modo catálogo, la RLS deja la tabla
-- vacía, y el reporte de huérfanas SÍ responde. Tabla vacía + huérfanas llenas: tablero mudo.
-- canWriteModule/current_org_has_protocol_author son CAPACIDAD (el centro tiene el derecho); la
-- RLS pide AUTORIDAD (además, el rol). Misma confusión que la guarda inerte de roles del 8-sep.
--
-- Esta migración crea UNA autoridad —current_user_can_author_catalog()— y hace que las tres
-- puertas DERIVEN de ella. El Dart la refleja (canAuthorProtocolCatalog). Un guardia enumerado
-- (protocol_catalog_local_tests) revienta si nace una cuarta puerta que no derive de aquí.
-- =============================================================================

create or replace function public.current_user_can_author_catalog()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- AUTORIDAD (no capacidad): master, o admin del centro CON protocol:author vigente. Es
  -- EXACTAMENTE lo que exige la RLS de 0137; ahora vive en un solo lugar.
  select public.is_master()
      or (public.is_admin() and public.current_org_has_protocol_author());
$$;
comment on function public.current_user_can_author_catalog() is
  'Autoridad ÚNICA para ver/editar el catálogo Kura+ (protocol_catalog_rules): master O (admin '
  'del centro Y protocol:author vigente). La RLS y resolve_protocol_orphans DERIVAN de ella; el '
  'Dart la refleja en canAuthorProtocolCatalog. Rol + derecho, no solo derecho (capacidad).';

-- Puerta 1: la RLS deriva de la autoridad (misma lógica que 0137, ahora single-sourced).
drop policy if exists protocol_catalog_rules_all on public.protocol_catalog_rules;
create policy protocol_catalog_rules_all on public.protocol_catalog_rules
  for all
  using (public.current_user_can_author_catalog())
  with check (public.current_user_can_author_catalog());

-- Puerta 2: el reporte de huérfanas deriva de la autoridad. ANTES pedía solo
-- current_org_has_protocol_author() (sin rol) → un no-admin de Kura+ recibía huérfanas con la
-- tabla vacía. Ahora concuerda con la RLS: sin rol, no hay reporte.
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
  where public.current_user_can_author_catalog()   -- deriva de la autoridad única (antes: solo el derecho)
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
  'Reglas del CATÁLOGO Kura+ que no aterrizan en el inventario del centro (sin identidad o con '
  'identidad ausente). SOLO visible con autoridad de autoría (current_user_can_author_catalog): '
  'rol admin + protocol:author, o master. Concuerda con la RLS.';
