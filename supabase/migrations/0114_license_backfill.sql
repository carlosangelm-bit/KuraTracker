-- =============================================================================
-- 0114_license_backfill.sql — Backfill OBLIGATORIO de derechos (Fase 1, §3.4).
-- =============================================================================
-- Sin backfill, esta fase APAGA módulos en producción: cuando el AND (§4) y el
-- candado (§5) empiecen a exigir un derecho y ningún centro lo tenga, todos los
-- módulos se apagan para todos los centros existentes. Mismo riesgo (y misma
-- solución) que el paso 1 del 0100.
--
-- Reproduce el ESTADO EFECTIVO DE HOY, centro por centro:
--   · module:clinico  → siempre.
--   · module:insumos / module:comercial → si el módulo está hoy efectivamente
--       encendido (misma resolución que isModuleEnabled a nivel centro:
--       module_settings de centro, o defaultFor(tipo) = solo clínica de heridas).
--   · module:admin    → si el centro tiene más de un miembro activo.
--   · seat:clinico    → quantity = consumed_seats(org) (lo que YA consumen, para
--       que nadie quede por encima del tope el día del despliegue).
--   · seat:protocolo  → quantity = nº de perfiles del centro con premium_enabled,
--       solo si el centro tiene premium_protocolo_kura.
-- Todo con status='active', source='master', current_period_end=null (derechos
-- otorgados, no cobrados). Idempotente: on conflict do nothing.
--
-- INERTE: solo agrega filas de derechos; el comportamiento no cambia hasta 0115
-- (candado) y el AND en la app. Al final, un bloque que ABORTA la migración si
-- algún centro activo perdería un módulo bajo el AND (verificación antes del guard).
-- =============================================================================

-- 1) module:clinico — siempre.
insert into public.org_entitlements (organization_id, kind, key, status, source)
select o.id, 'module', 'clinico', 'active', 'master'
from public.organizations o
where o.is_active
on conflict (organization_id, kind, key) do nothing;

-- 2) module:insumos — si está efectivamente encendido a nivel centro.
insert into public.org_entitlements (organization_id, kind, key, status, source)
select o.id, 'module', 'insumos', 'active', 'master'
from public.organizations o
where o.is_active
  and coalesce(
    (select ms.enabled from public.module_settings ms
     where ms.organization_id = o.id and ms.module_key = 'insumos'
       and ms.site_id is null and ms.profile_id is null
     limit 1),
    o.center_type = 'clinica_heridas'   -- defaultFor(insumos)
  )
on conflict (organization_id, kind, key) do nothing;

-- 3) module:comercial — igual criterio.
insert into public.org_entitlements (organization_id, kind, key, status, source)
select o.id, 'module', 'comercial', 'active', 'master'
from public.organizations o
where o.is_active
  and coalesce(
    (select ms.enabled from public.module_settings ms
     where ms.organization_id = o.id and ms.module_key = 'comercial'
       and ms.site_id is null and ms.profile_id is null
     limit 1),
    o.center_type = 'clinica_heridas'   -- defaultFor(comercial)
  )
on conflict (organization_id, kind, key) do nothing;

-- 4) module:admin — si el centro tiene más de un miembro activo.
insert into public.org_entitlements (organization_id, kind, key, status, source)
select o.id, 'module', 'admin', 'active', 'master'
from public.organizations o
where o.is_active
  and (
    select count(*) from public.user_center_memberships m
    join public.profiles p on p.id = m.profile_id
    where m.organization_id = o.id and m.is_active and p.is_active
  ) > 1
on conflict (organization_id, kind, key) do nothing;

-- 5) seat:clinico — lo que ya consumen hoy (tope = uso actual, nadie por encima).
insert into public.org_entitlements (organization_id, kind, key, quantity, status, source)
select o.id, 'seat', 'clinico', public.consumed_seats(o.id), 'active', 'master'
from public.organizations o
where o.is_active
on conflict (organization_id, kind, key) do nothing;

-- 6) seat:protocolo — perfiles con premium_enabled, solo si el centro tiene el add-on.
insert into public.org_entitlements (organization_id, kind, key, quantity, status, source)
select o.id, 'seat', 'protocolo',
  (select count(*)::int from public.profiles p
   where p.organization_id = o.id and p.premium_enabled = true),
  'active', 'master'
from public.organizations o
where o.is_active
  and o.premium_protocolo_kura = true
on conflict (organization_id, kind, key) do nothing;

-- -----------------------------------------------------------------------------
-- Verificación ANTES del guard (§3.4, prueba de aceptación §9.1): ningún centro
-- activo debe perder un módulo bajo el AND. Compara el estado EFECTIVO de hoy
-- (module_settings/default) contra los derechos recién insertados; si a algún
-- centro le falta el derecho de un módulo que hoy muestra, ABORTA la migración
-- (rollback) — el backfill está mal y no se aplica nada.
-- -----------------------------------------------------------------------------
do $$
declare
  v_bad text;
begin
  select string_agg(format('org=%s falta module:%s', o.id, m.mk), ', ')
  into v_bad
  from public.organizations o
  cross join (values ('clinico'), ('insumos'), ('comercial')) as m(mk)
  where o.is_active
    and (case m.mk
           when 'clinico' then true
           else coalesce(
             (select ms.enabled from public.module_settings ms
              where ms.organization_id = o.id and ms.module_key = m.mk
                and ms.site_id is null and ms.profile_id is null
              limit 1),
             o.center_type = 'clinica_heridas')
         end)
    and not exists (
      select 1 from public.org_entitlements e
      where e.organization_id = o.id and e.kind = 'module' and e.key = m.mk
        and e.status = 'active'
    );

  if v_bad is not null then
    raise exception 'Backfill incompleto: algún centro perdería un módulo bajo el AND → %', v_bad;
  end if;
  raise notice 'Backfill de licencia verificado: ningún centro activo pierde un módulo.';
end $$;
