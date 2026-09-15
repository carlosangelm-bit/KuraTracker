-- =============================================================================
-- 0139_resolve_protocol.sql — Matriz del protocolo · ETAPA 2: el resolvedor en SQL
-- =============================================================================
-- CREA public.resolve_protocol() en SQL, espejo EXACTO del resolvedor de Dart
-- (data_repository.resolveProtocolProducts) sobre la tabla propia del centro, y lo extiende
-- al catálogo Kura+. NO retira el de Dart (eso es la etapa 3, solo con paridad probada).
--
-- 2.b — de qué fuente resuelve. El derecho SIEMPRE se pregunta por org_entitlement_vigente()
--   (etapa 1.5; no una cuarta consulta a org_entitlements):
--     · protocol:author  → resuelve contra protocol_catalog_rules.
--     · CONSUME Kura+     → contra protocol_catalog_rules, sin poder leerlo (esta fn es
--       SECURITY DEFINER: lee el catálogo y devuelve SOLO el régimen resuelto, nunca filas).
--       El derecho de consumo YA existe: seat:protocolo con quantity>=1 (Dart:
--       premiumProtocoloKuraFor → hasSeatEntitlement('protocolo')). No se inventa clave.
--     · sin Kura+         → contra su protocol_product_rules.
--
-- Salida: SOLO el régimen resuelto (paso, producto, marca, alternativa, cantidad,
-- note_phrase, fuente). NUNCA las reglas, condiciones, ni un renglón del catálogo.
--
-- HALLAZGO (§2.c) reportado a Carlos: el resolvedor de Dart ordena por (category, sort_order)
-- y NO usa `priority` en ningún punto (ni appliesTo, ni specificity, ni el orden). Para tener
-- PARIDAD, este SQL también ordena por sort_order e ignora priority. Si el de Dart está mal
-- (debería desempatar por priority), es decisión de Carlos y va aparte.
-- =============================================================================

create or replace function public.resolve_protocol(
  p_organization_id uuid,
  p_categories text[],                       -- KuraTag.dbValue de los pasos que emitió el motor
  p_area_cm2 numeric default null,
  p_volume_cm3 numeric default null,
  p_exudate_level text default null,         -- ExudadoCantidad.name
  p_zone_group text default null,            -- ZoneGroup key
  p_infection_suspected boolean default null,
  p_site_id uuid default null,
  p_context_kind text default null,          -- contexto nuevo (etiologia|piel|evolucion|null)
  p_context_value text default null
)
returns table (
  category text,
  inventory_item_id uuid,
  name text,             -- producto (del inventario del centro)
  quantity numeric,      -- cantidad resuelta
  brand text,            -- marca (columna nueva; null en reglas propias existentes)
  alt_name text,         -- alternativa
  alt_brand text,
  note_phrase text,
  source text            -- 'kura' | 'propio'
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_use_catalog boolean;
begin
  -- 2.b — fuente. Autoridad ÚNICA de vigencia (etapa 1.5). Consumo = seat:protocolo vigente
  -- con cupo>=1. Autoría = module:protocol:author vigente.
  v_use_catalog :=
       public.org_entitlement_vigente(p_organization_id, 'module', 'protocol:author')
    or (public.org_entitlement_vigente(p_organization_id, 'seat', 'protocolo')
        and coalesce((
          select e.quantity from public.org_entitlements e
          where e.organization_id = p_organization_id
            and e.kind = 'seat' and e.key = 'protocolo'
        ), 0) >= 1);

  return query
  with
  -- Inventario del centro (+ sitio si se pasa), SIN filtro de activo (Dart: activeOnly:false).
  inv as (
    select i.id, i.name
    from public.inventory_items i
    where i.organization_id = p_organization_id
      and (p_site_id is null or i.site_id = p_site_id)
  ),
  -- Reglas de la fuente elegida. El contexto (context_kind/value) filtra el CATÁLOGO
  -- (una regla de catálogo con contexto aplica solo si calza o si es null=todo); en la tabla
  -- propia esas columnas son null → no filtran (paridad con Dart, que no las conoce).
  src as (
    select r.category, r.inventory_item_id, r.dimension,
           r.min_value, r.max_value, r.quantity_mode, r.quantity_value, r.sort_order,
           r.exudate_levels, r.zone_groups, r.infection,
           r.brand, r.alt_name, r.alt_brand, r.note_phrase, r.context_kind, r.context_value
    from public.protocol_catalog_rules r
    where v_use_catalog
    union all
    select r.category, r.inventory_item_id, r.dimension,
           r.min_value, r.max_value, r.quantity_mode, r.quantity_value, r.sort_order,
           r.exudate_levels, r.zone_groups, r.infection,
           r.brand, r.alt_name, r.alt_brand, r.note_phrase, r.context_kind, r.context_value
    from public.protocol_product_rules r
    where not v_use_catalog and r.organization_id = p_organization_id
  ),
  -- appliesTo() de Dart, condición por condición. Una condición con dato faltante NO aplica.
  applicable as (
    select s.*, iv.name as item_name,
           ( (case when s.dimension <> 'none' then 1 else 0 end)
           + (case when coalesce(jsonb_array_length(s.exudate_levels), 0) > 0 then 1 else 0 end)
           + (case when coalesce(jsonb_array_length(s.zone_groups), 0) > 0 then 1 else 0 end)
           + (case when s.infection <> 'any' then 1 else 0 end) ) as spec
    from src s
    join inv iv on iv.id = s.inventory_item_id   -- huérfanas (item ausente) se saltan (Dart)
    where s.category = any(p_categories)
      and s.inventory_item_id is not null
      -- medida (dimensión + rango [min, max))
      and (
        s.dimension = 'none'
        or (s.dimension = 'area'   and p_area_cm2   is not null
            and (s.min_value is null or p_area_cm2   >= s.min_value)
            and (s.max_value is null or p_area_cm2   <  s.max_value))
        or (s.dimension = 'volume' and p_volume_cm3 is not null
            and (s.min_value is null or p_volume_cm3 >= s.min_value)
            and (s.max_value is null or p_volume_cm3 <  s.max_value))
      )
      -- exudado
      and (coalesce(jsonb_array_length(s.exudate_levels), 0) = 0
           or (p_exudate_level is not null and s.exudate_levels ? p_exudate_level))
      -- zona
      and (coalesce(jsonb_array_length(s.zone_groups), 0) = 0
           or (p_zone_group is not null and s.zone_groups ? p_zone_group))
      -- infección
      and (s.infection = 'any'
           or (p_infection_suspected is not null
               and ((s.infection = 'yes' and p_infection_suspected)
                 or (s.infection = 'no'  and not p_infection_suspected))))
      -- contexto (solo aplica al catálogo; en la propia es null=todo)
      and (s.context_kind is null
           or (p_context_kind is not null and s.context_kind = p_context_kind
               and (s.context_value is null or s.context_value = p_context_value)))
  ),
  -- Gana la MÁS ESPECÍFICA por categoría; empate → todas (dedup por item, gana el de menor
  -- sort_order, que es lo que Dart emite primero en su orden category,sort_order).
  maxspec as (
    select a.category, max(a.spec) as ms from applicable a group by a.category
  ),
  ranked as (
    select a.*,
           row_number() over (
             partition by a.category, a.inventory_item_id
             order by a.sort_order
           ) as rn_item
    from applicable a
    join maxspec m on m.category = a.category and a.spec = m.ms
  )
  select
    r.category,
    r.inventory_item_id,
    r.item_name as name,
    case r.quantity_mode
      when 'per_area'   then coalesce(p_area_cm2, 0)   * r.quantity_value
      when 'per_volume' then coalesce(p_volume_cm3, 0) * r.quantity_value
      else r.quantity_value
    end as quantity,
    r.brand, r.alt_name, r.alt_brand, r.note_phrase,
    case when v_use_catalog then 'kura' else 'propio' end as source
  from ranked r
  where r.rn_item = 1
  order by r.category, r.sort_order;
end;
$$;

comment on function public.resolve_protocol(uuid, text[], numeric, numeric, text, text, boolean, uuid, text, text) is
  'Resuelve el protocolo → régimen (paso, producto, marca, alternativa, cantidad, note, '
  'fuente). Espejo del resolvedor de Dart sobre protocol_product_rules; extiende al catálogo '
  'Kura+ (protocol:author o consumo seat:protocolo, vía org_entitlement_vigente). SECURITY '
  'DEFINER: el que CONSUME recibe el régimen sin poder leer el catálogo. Devuelve SOLO el '
  'régimen, nunca reglas ni renglones. NO usa priority (paridad con Dart; ver 0139).';

-- -----------------------------------------------------------------------------
-- 2.e — Huérfanas del CATÁLOGO. El resolvedor SALTA en silencio las reglas cuyo producto no
-- está en el inventario del centro; esto las hace visibles para verificar la siembra (etapa 5)
-- y cazar errores de clasificación. Mismo criterio/razón que orphanProtocolRules de Dart (la
-- tabla propia la sigue reportando Dart, intacto). Este reporte SOLO lo ve quien tenga
-- protocol:author — a un centro que CONSUME no se le filtra por aquí lo que no ve por la puerta.
-- SECURITY DEFINER (para leer el catálogo), pero con la GUARDA de author en el cuerpo.
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
  select r.id, r.category, r.inventory_item_id,
         case when r.inventory_item_id is null then 'sin insumo asignado'
              else 'el insumo no está en este '
                   || case when p_site_id is null then 'centro' else 'sitio' end
         end
  from public.protocol_catalog_rules r
  where public.current_org_has_protocol_author()   -- GUARDA: solo author ve el reporte
    and (
      r.inventory_item_id is null
      or not exists (
        select 1 from public.inventory_items i
        where i.id = r.inventory_item_id
          and i.organization_id = p_organization_id
          and (p_site_id is null or i.site_id = p_site_id)
      )
    );
$$;
comment on function public.resolve_protocol_orphans(uuid, uuid) is
  'Reglas del CATÁLOGO Kura+ cuyo producto no existe en el inventario del centro (sin insumo, '
  'o insumo ausente del centro/sitio). Hace visibles las que resolve_protocol salta en '
  'silencio. SOLO visible con protocol:author. La tabla propia la reporta Dart '
  '(orphanProtocolRules), intacto.';
