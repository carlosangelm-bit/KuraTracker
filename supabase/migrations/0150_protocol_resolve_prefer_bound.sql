-- 0150_protocol_resolve_prefer_bound.sql
-- =============================================================================
-- REGRESIÓN del left join de 0149 (medida por Carlos): al dejar que la regla propia SIN insumo del
-- centro participe (huérfana con nombre), esa regla entra en el cálculo de especificidad; si es MÁS
-- específica que una regla SÍ atada, la DESPLAZA (maxspec se calcula sobre TODAS las aplicables y
-- luego `join maxspec on spec = ms` elimina las de menor especificidad, entre ellas la única con
-- insumo). El clínico pasa de un insumo usable a solo un nombre.
--
-- ARREGLO (Carlos): ESTAR ATADA MANDA SOBRE SER ESPECÍFICA. Por categoría, si hay al menos una
-- regla CON insumo del centro, solo esas compiten (y entre ellas gana la más específica); se cae a
-- las NO atadas solo si NINGUNA está atada —así la huérfana con nombre sigue saliendo cuando es la
-- única opción, pero no desplaza a una usable—. Es un cambio en la selección (maxspec), no en los
-- filtros: el filtro de sitio sigue retirado (0149). Solo cambia el CAMINO PROPIO (donde vive la
-- regresión); el camino catálogo queda idéntico a 0149.
-- =============================================================================
create or replace function public.resolve_protocol(
  p_organization_id uuid,
  p_categories text[],
  p_area_cm2 numeric default null,
  p_volume_cm3 numeric default null,
  p_exudate_level text default null,
  p_zone_group text default null,
  p_infection_suspected boolean default null,
  p_site_id uuid default null,            -- CONSERVADO por firma; NO filtra (0149)
  p_context_kind text default null,
  p_context_value text default null
)
returns table (
  category text,
  inventory_item_id uuid,
  name text,
  quantity numeric,
  brand text,
  alt_name text,
  alt_brand text,
  note_phrase text,
  source text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_use_catalog boolean;
begin
  if not public.org_entitlement_vigente(p_organization_id, 'module', 'admin') then
    v_use_catalog := true;
  else
    v_use_catalog := coalesce((
      select o.protocol_resolves_from_catalog
      from public.organizations o where o.id = p_organization_id), true);
  end if;

  if not v_use_catalog then
    -- CAMINO PROPIO — SIN filtro de sitio (0149); LEFT JOIN (la regla sin insumo sale con item
    -- null y el nombre de la regla); y PREFIERE ATADA sobre específica (0150).
    return query
    with
    inv as (
      select i.id, i.name
      from public.inventory_items i
      where i.organization_id = p_organization_id
      -- SIN `and (p_site_id is null or i.site_id = p_site_id)` (0149): el insumo cuenta esté en el
      -- sitio que esté. Reponerlo rompe la prueba de mutación de resolve_protocol_behavior.
    ),
    applicable as (
      select r.id, r.category, r.inventory_item_id, r.name as rule_name, r.sort_order,
             r.quantity_mode, r.quantity_value, r.brand, r.alt_name, r.alt_brand, r.note_phrase,
             iv.id as matched_item, iv.name as item_name,
             ( (case when r.dimension <> 'none' then 1 else 0 end)
             + (case when coalesce(jsonb_array_length(r.exudate_levels), 0) > 0 then 1 else 0 end)
             + (case when coalesce(jsonb_array_length(r.zone_groups), 0) > 0 then 1 else 0 end)
             + (case when r.infection <> 'any' then 1 else 0 end) ) as spec
      from public.protocol_product_rules r
      left join inv iv on iv.id = r.inventory_item_id
      where r.organization_id = p_organization_id
        and r.category = any(p_categories)
        and r.inventory_item_id is not null
        and (
          r.dimension = 'none'
          or (r.dimension = 'area'   and p_area_cm2   is not null
              and (r.min_value is null or p_area_cm2   >= r.min_value)
              and (r.max_value is null or p_area_cm2   <  r.max_value))
          or (r.dimension = 'volume' and p_volume_cm3 is not null
              and (r.min_value is null or p_volume_cm3 >= r.min_value)
              and (r.max_value is null or p_volume_cm3 <  r.max_value))
        )
        and (coalesce(jsonb_array_length(r.exudate_levels), 0) = 0
             or (p_exudate_level is not null and r.exudate_levels ? p_exudate_level))
        and (coalesce(jsonb_array_length(r.zone_groups), 0) = 0
             or (p_zone_group is not null and r.zone_groups ? p_zone_group))
        and (r.infection = 'any'
             or (p_infection_suspected is not null
                 and ((r.infection = 'yes' and p_infection_suspected)
                   or (r.infection = 'no'  and not p_infection_suspected))))
        and (r.context_kind is null
             or (p_context_kind is not null and r.context_kind = p_context_kind
                 and (r.context_value is null or r.context_value = p_context_value)))
    ),
    -- PREFERIR ATADA (0150): ¿la categoría tiene alguna regla con insumo del centro?
    hasbound as (
      select a.category, bool_or(a.matched_item is not null) as any_bound
      from applicable a group by a.category
    ),
    -- Si la hay, solo compiten las atadas; si no, compiten las no atadas (huérfana sola).
    tier as (
      select a.*
      from applicable a
      join hasbound h on h.category = a.category
      where a.matched_item is not null or not h.any_bound
    ),
    maxspec as (
      select t.category, max(t.spec) as ms from tier t group by t.category
    ),
    ranked as (
      select t.*,
             row_number() over (
               partition by t.category,
                 coalesce(t.matched_item::text, 'rule:' || t.id::text)
               order by t.sort_order
             ) as rn_item
      from tier t
      join maxspec m on m.category = t.category and t.spec = m.ms
    )
    select
      r.category, r.matched_item as inventory_item_id,
      coalesce(r.item_name, r.rule_name) as name,
      case r.quantity_mode
        when 'per_area'   then coalesce(p_area_cm2, 0)   * r.quantity_value
        when 'per_volume' then coalesce(p_volume_cm3, 0) * r.quantity_value
        else r.quantity_value
      end as quantity,
      r.brand, r.alt_name, r.alt_brand, r.note_phrase, 'propio'::text as source
    from ranked r
    where r.rn_item = 1
    order by r.category, r.sort_order;
    return;
  end if;

  -- CAMINO CATÁLOGO — idéntico a 0149 (SIN filtro de sitio). NO se toca aquí: la regresión medida
  -- vive en el camino propio. (El camino catálogo tiene la misma FORMA —maxspec sobre matched,
  -- huérfanas con item null— y podría exhibir el mismo desplazamiento; queda anotado para decisión
  -- de Carlos, no se cambia en silencio.)
  return query
  with
  applicable as (
    select r.id, r.category, r.sort_order, r.quantity_mode, r.quantity_value,
           r.name, r.brand, r.alt_name, r.alt_brand, r.note_phrase,
           r.shopify_product_id, r.shopify_variant_id,
           ( (case when r.dimension <> 'none' then 1 else 0 end)
           + (case when coalesce(jsonb_array_length(r.exudate_levels), 0) > 0 then 1 else 0 end)
           + (case when coalesce(jsonb_array_length(r.zone_groups), 0) > 0 then 1 else 0 end)
           + (case when r.infection <> 'any' then 1 else 0 end) ) as spec
    from public.protocol_catalog_rules r
    where r.category = any(p_categories)
      and (
        r.dimension = 'none'
        or (r.dimension = 'area'   and p_area_cm2   is not null
            and (r.min_value is null or p_area_cm2   >= r.min_value)
            and (r.max_value is null or p_area_cm2   <  r.max_value))
        or (r.dimension = 'volume' and p_volume_cm3 is not null
            and (r.min_value is null or p_volume_cm3 >= r.min_value)
            and (r.max_value is null or p_volume_cm3 <  r.max_value))
      )
      and (coalesce(jsonb_array_length(r.exudate_levels), 0) = 0
           or (p_exudate_level is not null and r.exudate_levels ? p_exudate_level))
      and (coalesce(jsonb_array_length(r.zone_groups), 0) = 0
           or (p_zone_group is not null and r.zone_groups ? p_zone_group))
      and (r.infection = 'any'
           or (p_infection_suspected is not null
               and ((r.infection = 'yes' and p_infection_suspected)
                 or (r.infection = 'no'  and not p_infection_suspected))))
      and (r.context_kind is null
           or (p_context_kind is not null and r.context_kind = p_context_kind
               and (r.context_value is null or r.context_value = p_context_value)))
  ),
  matched as (
    select a.*,
           (select ii.id from public.inventory_items ii
             where ii.organization_id = p_organization_id
               and a.shopify_product_id is not null
               and ii.shopify_product_id = a.shopify_product_id
               and coalesce(ii.shopify_variant_id, '') = coalesce(a.shopify_variant_id, '')
             order by ii.id
             limit 1) as matched_item
    from applicable a
  ),
  maxspec as (
    select m.category, max(m.spec) as ms from matched m group by m.category
  ),
  ranked as (
    select m.*,
           row_number() over (
             partition by m.category,
               coalesce(m.shopify_product_id || '|' || coalesce(m.shopify_variant_id, ''),
                        'rule:' || m.id::text)
             order by m.sort_order
           ) as rn_item
    from matched m
    join maxspec x on x.category = m.category and m.spec = x.ms
  )
  select
    r.category, r.matched_item as inventory_item_id, r.name,
    case r.quantity_mode
      when 'per_area'   then coalesce(p_area_cm2, 0)   * r.quantity_value
      when 'per_volume' then coalesce(p_volume_cm3, 0) * r.quantity_value
      else r.quantity_value
    end as quantity,
    r.brand, r.alt_name, r.alt_brand, r.note_phrase, 'kura'::text as source
  from ranked r
  where r.rn_item = 1
  order by r.category, r.sort_order;
end;
$$;
