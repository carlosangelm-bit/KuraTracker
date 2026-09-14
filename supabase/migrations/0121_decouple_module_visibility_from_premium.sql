-- =============================================================================
-- 0121_decouple_module_visibility_from_premium.sql — Separar VISIBILIDAD de PAGO
-- para Insumos y Comercial (verificación de fase 2, opción A).
-- =============================================================================
-- Fase 1 colgó la visibilidad del nav Y el pago de la MISMA clave (module:insumos):
-- isModuleEnabled exige module:insumos para MOSTRAR Insumos (data_repository:880), y
-- el 0114 se lo otorgó a TODA clínica de heridas por visibilidad (default-on), no por
-- pago. Rerutear el candado premium a ese derecho regalaría Insumos/Comercial premium
-- a toda la cartera. La app ya no lo hace: ModuleKey.entitlementKey de Insumos y
-- Comercial pasó a 'clinico', así que su VISIBILIDAD monta sobre module:clinico (que
-- todo centro tiene) + module_settings/default, y module:insumos / module:comercial
-- quedan como SOLO el candado de PAGO (premiumInsumosFor/premiumComercialFor).
--
-- Esta migración alinea la BASE con ese modelo, de forma ADITIVA (0113-0120 ya están
-- aplicadas en el sandbox; no se editan, para no romper el historial de db push):
--   1) Limpia los module:insumos/comercial que el 0114 otorgó por VISIBILIDAD, no por
--      pago (source='master' y el centro NO tenía premium_insumos). No toca los de
--      source='stripe' (compras reales) ni los de centros que sí tenían la bandera.
--   2) Afloja el candado del 0115 para insumos/comercial: encender esos módulos exige
--      module:clinico (su nueva clave de visibilidad), no el homónimo. El paywall de
--      adentro aguanta el pago. (Carlos, 10-sep: mejor embudo — el centro lo ve, lo
--      quiere, choca con el paywall, lo compra.)
--   3) Extiende el trigger del 0100 para que activar premium por usuario funcione
--      cuando el centro contrató seat:protocolo (comprado por Stripe), no solo con la
--      bandera legada premium_protocolo_kura.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Limpieza del sobre-otorgamiento del 0114 (visibilidad, no pago).
--    IMPORTANTE: solo source='master' (artefacto del backfill) y solo donde el
--    centro NO tenía premium_insumos. Preserva compras de Stripe y comps del master
--    a centros con la bandera. Sin datos de prod (main en 0107): en la práctica solo
--    afecta a los centros de prueba del sandbox.
-- -----------------------------------------------------------------------------
delete from public.org_entitlements e
using public.organizations o
where e.organization_id = o.id
  and e.kind = 'module'
  and e.key in ('insumos', 'comercial')
  and e.source = 'master'
  and coalesce(o.premium_insumos, false) = false;

-- -----------------------------------------------------------------------------
-- 2. Candado de module_settings: insumos/comercial exigen 'clinico' (su clave de
--    visibilidad), no el homónimo. Redefine la función del 0115; el trigger no cambia.
-- -----------------------------------------------------------------------------
create or replace function public.enforce_module_requires_entitlement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_required text;
  v_label text;
begin
  if new.enabled is not true then
    return new;
  end if;
  if public.is_master() then
    return new;
  end if;

  -- Todos los módulos gobiernan su VISIBILIDAD con module:clinico; insumos/comercial
  -- ya no exigen su clave homónima (ésa es el candado de PAGO, adentro). El único
  -- derecho de visibilidad hoy es clinico (los demás módulos ya usaban clinico).
  v_required := 'clinico';
  v_label := 'Clínico';

  if not exists (
    select 1 from public.org_entitlements e
    where e.organization_id = new.organization_id
      and e.kind = 'module'
      and e.key = v_required
      and e.status = 'active'
  ) then
    raise exception 'El centro no tiene contratado el módulo %.', v_label;
  end if;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Trigger del 0100: activar premium por usuario también vale si el centro
--    contrató seat:protocolo (Stripe), no solo con la bandera legada.
-- -----------------------------------------------------------------------------
create or replace function public.enforce_premium_requires_org_addon()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.premium_enabled = true
     and (tg_op = 'INSERT'
          or coalesce(old.premium_enabled, false) is distinct from new.premium_enabled) then
    if not exists (
      select 1 from public.organizations o
      where o.id = new.organization_id and o.premium_protocolo_kura = true
    ) and not exists (
      select 1 from public.org_entitlements e
      where e.organization_id = new.organization_id
        and e.kind = 'seat' and e.key = 'protocolo'
        and e.status = 'active' and coalesce(e.quantity, 0) >= 1
    ) then
      raise exception
        'El centro no tiene el add-on Protocolo Kura+; no se puede activar premium por usuario.';
    end if;
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. El nombre miente un poco, a propósito (§2.3): de aquí en adelante
--    module:insumos / module:comercial NO significan "el módulo" (eso es visibilidad,
--    montada sobre clinico) sino "el PREMIUM del módulo" (el paywall interno). Se deja
--    escrito para que nadie lo vuelva a colapsar al "limpiar" el modelo.
-- -----------------------------------------------------------------------------
comment on table public.org_entitlements is
  'Derechos vigentes de un centro (lo que PAGÓ). OJO: module:insumos y module:comercial '
  'significan el PREMIUM (paywall interno) del módulo, NO su visibilidad — ésa monta '
  'sobre module:clinico (ver ModuleKey.entitlementKey, decoupling 0121). Escritura solo '
  'master o el webhook de Stripe (service_role); el admin del centro NO escribe aquí.';
comment on table public.billing_catalog is
  'Traducción lookup_key de Stripe → (kind, key, interval, unit). OJO: module:insumos y '
  'module:comercial venden el PREMIUM del módulo (paywall), no su visibilidad (0121). La '
  'clave es idéntica en prueba/prod; stripe_price_id es informativo por entorno.';
