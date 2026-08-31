-- =============================================================================
-- 0100_premium_requires_org_addon.sql — Premium Kura+ = add-on de CENTRO AND usuario
-- =============================================================================
-- Modelo de licencias (brief 31-ago-2026 §4): el Protocolo Kura+ se COMPRA a
-- nivel centro (organizations.premium_protocolo_kura, 0049) y el centro decide a
-- QUIÉN se lo asigna (profiles.premium_enabled). Antes la app lo resolvía como un
-- OR (add-on de centro O premium de usuario), que habilitaba Kura+ para todo el
-- centro o para cualquier usuario marcado aunque el centro no hubiera comprado el
-- add-on — hueco de ingresos. Pasa a AND (ver kuraProtocolEnabledProvider).
--
-- Este cambio de lógica, sin backfill, APAGARÍA Kura+ a quien hoy lo tiene por el
-- add-on del centro pero sin premium_enabled=true. El paso 1 lo evita. El paso 2
-- impide, desde la base, otorgar premium individual en un centro sin el add-on
-- (no depender solo del cliente).
-- =============================================================================

-- 1) Backfill OBLIGATORIO: quien está en un centro CON el add-on conserva Kura+
--    (se le fija premium_enabled=true para que el AND siga dándoselo). No toca a
--    usuarios de centros sin add-on: esos justamente NO debían tenerlo (el hueco).
update public.profiles p
set premium_enabled = true
where p.premium_enabled is distinct from true
  and exists (
    select 1 from public.organizations o
    where o.id = p.organization_id and o.premium_protocolo_kura = true
  );

-- 2) Trigger: no se puede ACTIVAR premium_enabled si el centro no tiene el add-on.
--    Solo se dispara cuando premium_enabled pasa a true (o INSERT con true); NO se
--    incluye organization_id en el `update of` a propósito: cambiar de centro
--    (set_active_center) NO debe bloquearse — el AND ya apaga la capacidad si el
--    centro destino no tiene el add-on, sin tocar el flag. Quitar premium siempre pasa.
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
    ) then
      raise exception
        'El centro no tiene el add-on Protocolo Kura+; no se puede activar premium por usuario.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_premium_requires_org_addon on public.profiles;
create trigger trg_enforce_premium_requires_org_addon
  before insert or update of premium_enabled on public.profiles
  for each row execute function public.enforce_premium_requires_org_addon();
