-- 0149_protocol_resolve_no_site_filter.sql
-- =============================================================================
-- EL FLUJO DE INSUMOS NUNCA SE LIMITA POR EXISTENCIAS (spec de Carlos, 19-sep-2026). El estado
-- del inventario NUNCA impide registrar lo que clínicamente se usó; el inventario se cuadra
-- después, en su módulo. La existencia puede quedar negativa: eso es información, no un error.
--
-- Dos cambios a resolve_protocol (la jerarquía module:admin + interruptor de 0148 NO cambia):
--
-- 1) SE QUITA EL FILTRO DE SITIO en los DOS caminos. La regla del protocolo se configura para
--    TODO el centro (protocol_product_rules no tiene columna de sitio), pero el insumo vive por
--    sitio (inventory_items.site_id). Cruzarlos filtrando por p_site_id hacía que una regla del
--    centro atada a un insumo del Almacén NO resolviera para quien atiende en un consultorio
--    (medido en sandbox: mismo llamado, con el sitio de la paciente → [], sin sitio → resuelve).
--    p_site_id SE CONSERVA en la firma (hay llamadores) pero YA NO FILTRA — a propósito, no es un
--    olvido: reponerlo vuelve a romper el caso (hay prueba de mutación en resolve_protocol_behavior).
--    Cuadrar existencias entre sitios es trabajo del módulo de Insumos, posterior al lanzamiento.
--
-- 2) EL CAMINO PROPIO deja de SALTAR EN SILENCIO la regla cuyo insumo no aparece. Antes hacía
--    `join inv` (inner) y la desaparecía; ahora `left join` y la SACA con inventory_item_id null y
--    el nombre de la regla — igual que el camino catálogo ("huérfana con nombre"). El clínico ve lo
--    que el protocolo indica aunque el inventario no lo respalde, y decide. La UI ya dibuja
--    "· sin insumo enlazado".
-- =============================================================================
create or replace function public.resolve_protocol(
  p_organization_id uuid,
  p_categories text[],
  p_area_cm2 numeric default null,
  p_volume_cm3 numeric default null,
  p_exudate_level text default null,
  p_zone_group text default null,
  p_infection_suspected boolean default null,
  p_site_id uuid default null,            -- CONSERVADO por firma; NO filtra (spec 19-sep, ver arriba)
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
  -- QUIÉN DECIDE LA FUENTE (0148): module:admin + el interruptor. Sin Administración → Kura+.
  if not public.org_entitlement_vigente(p_organization_id, 'module', 'admin') then
    v_use_catalog := true;
  else
    v_use_catalog := coalesce((
      select o.protocol_resolves_from_catalog
      from public.organizations o where o.id = p_organization_id), true);
  end if;

  if not v_use_catalog then
    -- CAMINO PROPIO — reglas del centro. SIN filtro de sitio; LEFT JOIN para no desaparecer la
    -- regla cuyo insumo no está en el centro (sale con item null y el nombre de la regla).
    return query
    with
    inv as (
      select i.id, i.name
      from public.inventory_items i
      where i.organization_id = p_organization_id
      -- SIN `and (p_site_id is null or i.site_id = p_site_id)`: el insumo cuenta esté en el
      -- sitio que esté (Almacén, consultorio…). Reponerlo rompe la prueba de mutación.
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
    maxspec as (
      select a.category, max(a.spec) as ms from applicable a group by a.category
    ),
    ranked as (
      select a.*,
             row_number() over (
               partition by a.category,
                 coalesce(a.matched_item::text, 'rule:' || a.id::text) -- item null → dedup por regla
               order by a.sort_order
             ) as rn_item
      from applicable a
      join maxspec m on m.category = a.category and a.spec = m.ms
    )
    select
      r.category, r.matched_item as inventory_item_id,
      coalesce(r.item_name, r.rule_name) as name,  -- insumo no está → el nombre de la regla
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

  -- CAMINO CATÁLOGO — identidad → inventario del centro (SIN filtro de sitio); PROSA como
  -- name/brand/alt; huérfanas (sin identidad, o identidad que no aterriza) SALEN con item null.
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
               -- SIN `and (p_site_id is null or ii.site_id = p_site_id)`: identidad aterriza en
               -- el insumo del centro, esté en el sitio que esté (spec 19-sep).
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
