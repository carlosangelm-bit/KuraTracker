-- =============================================================================
-- 0140_protocol_catalog_identity.sql — Matriz del protocolo · ETAPA 5 (parte 1/2: identidad)
-- =============================================================================
-- La etapa 3 movió la resolución al servidor con selección de fuente EXCLUYENTE: un centro con
-- Kura+ (seat:protocolo o protocol:author) resuelve SOLO contra protocol_catalog_rules. Con el
-- catálogo vacío eso daba CERO filas en silencio. Esta etapa lo llena; aquí va el modelo de
-- IDENTIDAD que el catálogo necesita para nombrar un producto sin apuntar al insumo de UN centro.
--
-- IDENTIDAD (ya existe, no se inventa): product_catalog (0067) es identidad del SISTEMA (sin
-- organization_id) con el par shopify_product_id + shopify_variant_id; inventory_items (0050) ya
-- carga ese par. El puente centro→identidad está puesto. La regla del catálogo guarda ese par;
-- resolve_protocol lo resuelve contra los inventory_items del centro (acotado por org y SITIO,
-- que el inventario es por sitio). Sin coincidencia → huérfana reportada, NO silencio.
--
-- PROSA SIEMPRE: name/brand/alt viven en la regla como prosa (es lo que ve el clínico); la
-- identidad es lo que ATERRIZA en inventario y mueve consumo/reabasto. Una regla sin identidad
-- NO es error: es una huérfana con nombre, se resuelve igual (item null) y se reporta como tal.
-- (Hoja 2 del Excel v4: códigos/presentaciones sin validar → varias de las 35 nacen sin identidad.)
--
-- Las columnas nuevas van en AMBAS tablas (protocol_catalog_rules y protocol_product_rules) para
-- no romper la GUARDA DE DERIVA (0137 TEST4, paridad columna a columna salvo organization_id),
-- igual que hizo 0136 con context/scale/brand. En reglas PROPIAS no se usan (el centro apunta a su
-- inventory_item_id directo); existen solo por paridad.
-- =============================================================================

alter table public.protocol_catalog_rules
  add column if not exists shopify_product_id text, -- identidad (par con variant); null = sin identidad aún
  add column if not exists shopify_variant_id text,
  add column if not exists etapa_clinica      text, -- referencia (para la pantalla Matriz, etapa 6)
  add column if not exists notas              text; -- referencia clínica (documentación de la regla)

alter table public.protocol_product_rules
  add column if not exists shopify_product_id text, -- solo por paridad de deriva; no se usa en propias
  add column if not exists shopify_variant_id text,
  add column if not exists etapa_clinica      text,
  add column if not exists notas              text;

-- -----------------------------------------------------------------------------
-- resolve_protocol v2 — el camino PROPIO queda idéntico a 0139 (corpus-locked); el camino
-- CATÁLOGO cambia el join de inventory_item_id a IDENTIDAD (par shopify) contra el inventario del
-- centro, devuelve la PROSA como name/brand/alt, y NO salta las huérfanas: una regla sin
-- coincidencia sale con inventory_item_id NULL (el clínico ve el nombre; el reporte de huérfanas
-- la marca). dedup del catálogo por (category, identidad) — o por regla si no hay identidad, para
-- que dos huérfanas con nombre distinto no se colapsen entre sí.
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
  v_use_catalog :=
       public.org_entitlement_vigente(p_organization_id, 'module', 'protocol:author')
    or (public.org_entitlement_vigente(p_organization_id, 'seat', 'protocolo')
        and coalesce((
          select e.quantity from public.org_entitlements e
          where e.organization_id = p_organization_id
            and e.kind = 'seat' and e.key = 'protocolo'
        ), 0) >= 1);

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

comment on function public.resolve_protocol(uuid, text[], numeric, numeric, text, text, boolean, uuid, text, text) is
  'Resuelve el protocolo → régimen. Camino PROPIO (sin Kura+): reglas del centro por '
  'inventory_item_id, huérfanas se saltan. Camino CATÁLOGO (protocol:author o consumo '
  'seat:protocolo, vía org_entitlement_vigente): reglas del catálogo Kura+, identidad (par '
  'shopify) → inventario del centro (org+sitio); la PROSA name/brand/alt es lo que ve el clínico; '
  'sin coincidencia → item null (huérfana con nombre), NO se salta. NO usa priority.';

-- -----------------------------------------------------------------------------
-- resolve_protocol_orphans v2 — ahora por IDENTIDAD: una regla del catálogo es huérfana si no
-- tiene identidad (par shopify null) o si su identidad no aterriza en el inventario del
-- centro/sitio. Sigue siendo SOLO visible con protocol:author (guarda en el cuerpo).
-- -----------------------------------------------------------------------------
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
  where public.current_org_has_protocol_author()   -- GUARDA: solo author ve el reporte
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
  'Reglas del CATÁLOGO Kura+ que no aterrizan en el inventario del centro: sin identidad (par '
  'shopify null) o con identidad ausente del centro/sitio. Hace visibles las huérfanas con nombre '
  'que resolve_protocol devuelve con item null. SOLO con protocol:author.';
