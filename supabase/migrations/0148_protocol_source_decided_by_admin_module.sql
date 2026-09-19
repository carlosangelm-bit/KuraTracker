-- 0148_protocol_source_decided_by_admin_module.sql
-- =============================================================================
-- QUIÉN DECIDE LA MATRIZ DEL PROTOCOLO (spec de Carlos, 19-sep-2026). Sustituye la jerarquía
-- de 0145 (autor/asiento) por una regla nueva:
--   · Centro SIN module:admin  → SIEMPRE la matriz de Kura+ (no puede capturar la suya).
--   · Centro CON module:admin  → lo que elija su admin en el interruptor
--     (organizations.protocol_resolves_from_catalog); default true = Kura+.
--   · protocol:author SALE de esta decisión: su único trabajo vuelve a ser editar la matriz de
--     Kura+ (que es de Kura+). NO influye en qué resuelve un centro.
--   · El ASIENTO deja de decidir la fuente. Hoy tener seat:protocolo mandaba al centro a Kura+ e
--     ignoraba su matriz propia: ese es el defecto que se cierra.
-- Default para quien aún no elige: Kura+. Degradación: perder module:admin → vuelve a Kura+ por
-- la regla, sin estado huérfano ni tocar el interruptor.
--
-- Una sola decisión, TRES escritores (ya nos mordió antes tocar uno y olvidar los otros):
-- resolve_protocol (elige), set_org_resolves_from_catalog (RPC) y el trigger del interruptor.
-- Los dos candados de master se ABREN también al ADMIN del centro (con module:admin) sobre su
-- propio centro; master sigue pudiendo sobre cualquiera.
-- =============================================================================

-- 1) LA COLUMNA: default true (Kura+) + backfill. Se hace con el trigger del interruptor CAÍDO:
--    en una migración is_master() es false, así que el UPDATE del backfill lo rechazaría. Se
--    recrea el trigger abajo, ya con la condición nueva.
drop trigger if exists trg_zz_protocol_catalog_switch_master_only on public.organizations;

alter table public.organizations
  alter column protocol_resolves_from_catalog set default true;

-- Backfill: true a los centros SIN ninguna regla propia capturada (resuelven Kura+); los que SÍ
-- tienen matriz propia se dejan como están (están usándola, no hay por qué moverlos).
update public.organizations o
   set protocol_resolves_from_catalog = true
 where not exists (
   select 1 from public.protocol_product_rules r
   where r.organization_id = o.id
 );

-- 2) EL CANDADO DEL INTERRUPTOR (trigger). Ahora:
--    · UPDATE: lo cambia master, O el admin de ESE centro cuando el centro tiene module:admin.
--    · INSERT: SIN candado. El default pasó a true, así que TODA alta de centro (autoservicio,
--      create_trial_organization, alta de clientes) nace en true; rechazarlo tumbaría la creación
--      de centros. La columna solo importa para centros con module:admin, que la gobiernan por
--      UPDATE; en los demás resolve_protocol la ignora. La trampa de la rama INSERT de 0145 se
--      cierra quitándola a propósito, no descubriéndola en producción.
create or replace function public.enforce_catalog_switch_master_only()
returns trigger
language plpgsql
as $$
begin
  if new.protocol_resolves_from_catalog is distinct from old.protocol_resolves_from_catalog then
    if public.is_master() then
      null; -- master sobre cualquier centro
    elsif public.is_admin()
          and new.id = public.current_organization_id()
          and public.org_entitlement_vigente(new.id, 'module', 'admin') then
      null; -- admin del centro (con Administración) sobre su propio centro
    else
      raise exception 'Solo el master, o el admin del centro con Administración, puede cambiar '
        'desde dónde resuelve el protocolo (protocol_resolves_from_catalog)';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_zz_protocol_catalog_switch_master_only on public.organizations;
create trigger trg_zz_protocol_catalog_switch_master_only
  before update on public.organizations
  for each row execute function public.enforce_catalog_switch_master_only();

-- 3) EL RPC del interruptor (lo llama la pantalla; el trigger respalda cualquier UPDATE directo).
--    Misma condición: master, o admin del centro con module:admin sobre su propio centro.
create or replace function public.set_org_resolves_from_catalog(
  p_organization_id uuid,
  p_on boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not (
    public.is_master()
    or (public.is_admin()
        and p_organization_id = public.current_organization_id()
        and public.org_entitlement_vigente(p_organization_id, 'module', 'admin'))
  ) then
    raise exception 'Solo el master, o el admin del centro con Administración, puede cambiar '
      'desde dónde resuelve el protocolo';
  end if;
  update public.organizations
     set protocol_resolves_from_catalog = p_on
   where id = p_organization_id;
end;
$$;

-- 4) resolve_protocol — SOLO cambia el bloque que ELIGE la fuente (v_use_catalog). Los dos
--    caminos (propio y catálogo) quedan idénticos a 0145.
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
  -- QUIÉN DECIDE LA FUENTE (spec 19-sep): module:admin + el interruptor. Ni protocol:author ni
  -- el asiento deciden ya. Sin Administración no hay matriz propia que capturar → Kura+ siempre.
  if not public.org_entitlement_vigente(p_organization_id, 'module', 'admin') then
    v_use_catalog := true;
  else
    v_use_catalog := coalesce((
      select o.protocol_resolves_from_catalog
      from public.organizations o where o.id = p_organization_id), true);
  end if;

  if not v_use_catalog then
    -- CAMINO PROPIO — reglas del centro, join directo por inventory_item_id, huérfanas se saltan.
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
