-- =============================================================================
-- 0145_protocol_resolve_source_hierarchy.sql — Matriz del protocolo · §15 (desacople, arreglo)
-- =============================================================================
-- 0144 dejó v_use_catalog como DISYUNCIÓN: (seat y cupo>=1) OR (author y interruptor). Kura+ tiene
-- seat:protocolo (cupo 12, para su propio personal), así que la rama del asiento da true y el
-- interruptor NUNCA se evalúa: al aterrizar el bloque, Kura+ resolvería las 35 del catálogo con
-- identidad nula. El desacople quedaba INERTE justo para el centro que venía a proteger.
--
-- La semántica correcta es JERARQUÍA: ser AUTOR manda sobre tener asiento. Autor → decide el
-- interruptor; no-autor → seat decide. Además, el candado del interruptor se extiende a INSERT: un
-- centro nuevo no puede NACER resolviendo del catálogo salvo por master (antes solo cubría UPDATE).
-- =============================================================================

-- Candado del interruptor: ahora INSERT + UPDATE. La creación de centros (create_trial_organization,
-- alta de clientes) NO toca la columna → nace en false y pasa; un INSERT que la ponga en true sin
-- ser master se rechaza.
create or replace function public.enforce_catalog_switch_master_only()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.protocol_resolves_from_catalog and not public.is_master() then
      raise exception 'Solo el master puede crear un centro resolviendo del catálogo (protocol_resolves_from_catalog)';
    end if;
  elsif new.protocol_resolves_from_catalog is distinct from old.protocol_resolves_from_catalog
        and not public.is_master() then
    raise exception 'Solo el master puede cambiar desde dónde resuelve el protocolo (protocol_resolves_from_catalog)';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_zz_protocol_catalog_switch_master_only on public.organizations;
create trigger trg_zz_protocol_catalog_switch_master_only
  before insert or update on public.organizations
  for each row execute function public.enforce_catalog_switch_master_only();

-- -----------------------------------------------------------------------------
-- resolve_protocol v4 — igual que 0144 pero v_use_catalog es JERARQUÍA (autor → interruptor;
-- no-autor → seat). Ver el comentario en el cuerpo.
-- -----------------------------------------------------------------------------
create or replace function public.resolve_protocol(
  p_organization_id uuid,
  p_categories text[],
  p_area_cm2 numeric default null,
  p_volume_cm3 numeric default null,
  p_exudate_level text default null,
  p_zone_group text default null,
  p_infection_suspected boolean default null,
  p_site_id uuid default null,
  p_context_kind text default null,
  p_context_value text default null
)
returns table (
  category text,
  inventory_item_id uuid,   -- NULLABLE: en el catálogo, null = huérfana con nombre (sin stock enlazado)
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
  -- §15 JERARQUÍA (no disyunción): ser AUTOR manda sobre tener asiento. Un centro AUTOR resuelve
  -- según su INTERRUPTOR (organizations.protocol_resolves_from_catalog), tenga o no asiento; el
  -- asiento decide la fuente SOLO de quien NO es autor. Sin esto, Kura+ —que tiene seat:protocolo
  -- para su propio personal— resolvería el catálogo por la rama del asiento y el interruptor sería
  -- INERTE: el bug que el desacople venía a cerrar. Un interruptor que otro otorgamiento anula no
  -- es interruptor.
  if public.org_entitlement_vigente(p_organization_id, 'module', 'protocol:author') then
    v_use_catalog := coalesce((
      select o.protocol_resolves_from_catalog
      from public.organizations o where o.id = p_organization_id), false);
  else
    v_use_catalog :=
         public.org_entitlement_vigente(p_organization_id, 'seat', 'protocolo')
     and coalesce((
          select e.quantity from public.org_entitlements e
          where e.organization_id = p_organization_id
            and e.kind = 'seat' and e.key = 'protocolo'
        ), 0) >= 1;
  end if;

  if not v_use_catalog then
    -- CAMINO PROPIO — idéntico a 0139: reglas del centro, join directo por inventory_item_id,
    -- huérfanas (item ausente del centro/sitio) SE SALTAN, name del inventario.
    return query
    with
    inv as (
      select i.id, i.name
      from public.inventory_items i
      where i.organization_id = p_organization_id
        and (p_site_id is null or i.site_id = p_site_id)
    ),
    applicable as (
      select r.category, r.inventory_item_id, r.sort_order,
             r.quantity_mode, r.quantity_value, r.brand, r.alt_name, r.alt_brand, r.note_phrase,
             iv.name as item_name,
             ( (case when r.dimension <> 'none' then 1 else 0 end)
             + (case when coalesce(jsonb_array_length(r.exudate_levels), 0) > 0 then 1 else 0 end)
             + (case when coalesce(jsonb_array_length(r.zone_groups), 0) > 0 then 1 else 0 end)
             + (case when r.infection <> 'any' then 1 else 0 end) ) as spec
      from public.protocol_product_rules r
      join inv iv on iv.id = r.inventory_item_id
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
             row_number() over (partition by a.category, a.inventory_item_id order by a.sort_order) as rn_item
      from applicable a
      join maxspec m on m.category = a.category and a.spec = m.ms
    )
    select
      r.category, r.inventory_item_id, r.item_name as name,
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

  -- CAMINO CATÁLOGO — identidad → inventario del centro; PROSA como name/brand/alt; huérfanas
  -- (sin identidad, o identidad que no aterriza en el centro/sitio) SALEN con item null.
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
           -- identidad (par shopify) → un insumo del centro (org+sitio). Puede NO calzar → null.
           (select ii.id from public.inventory_items ii
             where ii.organization_id = p_organization_id
               and (p_site_id is null or ii.site_id = p_site_id)
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
                        'rule:' || m.id::text)     -- sin identidad → dedup por regla (no se colapsan)
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

