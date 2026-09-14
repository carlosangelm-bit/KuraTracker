-- =============================================================================
-- 0112_capable_clinico_by_profile.sql
-- =============================================================================
-- CORRECCIÓN de 0111 (que ya se aplicó en staging y por eso es INMUTABLE): 0111
-- medía la capacidad por `user_center_memberships.roles`, pero quién puede definir
-- planes lo decide el PERFIL (ver abajo). Esta migración REEMPLAZA los triggers y
-- funciones de 0111 por la versión basada en perfil. Es idempotente (create or
-- replace + drop/create trigger), así que corrige tanto el staging que ya aplicó
-- 0111 como un entorno nuevo que aplique 0111 y luego 0112. Al final se dejan las
-- funciones viejas de 0111 sin usar y se eliminan.
--
-- Guardia "el centro nunca se queda sin quien defina planes de cuidado" (huecos
-- #2/#3, 8-sep-2026 — decisión de Carlos: BLOQUEAR). Server-side de lo que la app
-- valida en setUserRoles / setUserActive, para el acceso directo por PostgREST.
--
-- CLAVE (corrección 8-sep): la CAPACIDAD de definir planes la decide el PERFIL,
-- NO la membresía. Es `canDiagnose` sobre el conjunto efectivo, con el rellenado
-- de gerencia clínica: un `admin` sin roles explícitos cuenta como {admin,clinico}.
-- La membresía por omisión NO trae 'clinico' (backfill 0106 deliberado), así que
-- medir user_center_memberships.roles dejaba fuera justo el caso del hospital. Aquí
-- la capacidad se lee de `profiles` y la membresía sólo define PERTENENCIA al centro.
--
-- Eventos que pueden dejar a un centro sin nadie capaz:
--   1) profiles: perder la capacidad (roles/role) o desactivar el perfil → un
--      perfil inactivo no puede iniciar sesión → sale de TODOS sus centros.
--   2) user_center_memberships: desactivar o borrar la membresía → sale de ESE
--      centro (incluye el borrado de perfil, que CASCADEA a la membresía).
--
-- Triggers `trg_zz_*` para correr DESPUÉS del sync role↔roles (0098/0106) y ver el
-- estado FINAL. SECURITY DEFINER + search_path para contar sin depender de la RLS.
-- Capacidad comparada por texto para no atarse al literal del enum.
-- =============================================================================

-- Capacidad de definir planes para una fila de perfil (roles user_role[], role
-- user_role): 'clinico' en el conjunto efectivo, con rellenado admin→{admin,clinico}
-- cuando roles viene vacío. Réplica de AppUser.canDiagnose.
create or replace function public.profile_can_define_plans(
  p_roles public.user_role[], p_role public.user_role
) returns boolean
language sql
immutable
as $$
  select case
    when coalesce(cardinality(p_roles), 0) > 0
      then 'clinico' = any(p_roles::text[])
    else p_role::text in ('admin', 'clinico')
  end;
$$;

-- ¿Queda algún usuario DISTINTO de p_exclude, con membresía ACTIVA en p_org y
-- perfil ACTIVO, que PUEDA definir planes?
create or replace function public.org_has_other_capable_profile(
  p_org uuid, p_exclude uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_center_memberships m
    join public.profiles pr on pr.id = m.profile_id
    where m.organization_id = p_org
      and m.profile_id <> p_exclude
      and m.is_active = true
      and pr.is_active = true
      and public.profile_can_define_plans(pr.roles, pr.role)
  );
$$;

-- Puerta 1: la membresía (PERTENENCIA). Desactivarla o borrarla saca al usuario
-- del centro; si su perfil podía definir planes y no queda otro capaz, se rechaza.
create or replace function public.prevent_membership_removes_last_capable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_capable boolean;
begin
  -- ¿El perfil dueño de la membresía afectada puede definir planes y está activo?
  select pr.is_active and public.profile_can_define_plans(pr.roles, pr.role)
    into v_capable
    from public.profiles pr
    where pr.id = old.profile_id;

  -- Solo importa si la membresía estaba activa y su perfil es capaz.
  if not (old.is_active and coalesce(v_capable, false)) then
    return coalesce(new, old);
  end if;
  -- UPDATE que MANTIENE la membresía activa: no se pierde pertenencia.
  if tg_op = 'UPDATE' and new.is_active then
    return new;
  end if;
  -- Desactivación o borrado: ¿queda otro capaz en el centro?
  if public.org_has_other_capable_profile(old.organization_id, old.profile_id) then
    return coalesce(new, old);
  end if;
  raise exception 'No autorizado: el centro se quedaría sin personal sanitario (nadie podría definir planes de cuidado).';
end;
$$;

drop trigger if exists trg_zz_prevent_org_without_clinico
  on public.user_center_memberships;
drop trigger if exists trg_zz_prevent_membership_removes_last_capable
  on public.user_center_memberships;
create trigger trg_zz_prevent_membership_removes_last_capable
  before update or delete on public.user_center_memberships
  for each row execute function public.prevent_membership_removes_last_capable();

-- Puerta 2: el perfil (CAPACIDAD). Perder canDiagnose (roles/role) o desactivar
-- el perfil lo saca de TODOS sus centros; si en alguno era el último capaz, se
-- rechaza.
create or replace function public.prevent_profile_removes_last_capable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_was boolean;
  v_now boolean;
begin
  v_was := old.is_active
       and public.profile_can_define_plans(old.roles, old.role);
  -- No era capaz+activo → no puede estar quitando el último capaz.
  if not v_was then
    return new;
  end if;
  v_now := new.is_active
       and public.profile_can_define_plans(new.roles, new.role);
  -- Sigue capaz+activo → no se pierde nada.
  if v_now then
    return new;
  end if;
  -- Perdió capacidad o se desactivó: revisar cada centro donde es miembro activo.
  for v_org in
    select m.organization_id
    from public.user_center_memberships m
    where m.profile_id = old.id
      and m.is_active = true
  loop
    if not public.org_has_other_capable_profile(v_org, old.id) then
      raise exception 'No autorizado: el centro se quedaría sin personal sanitario (nadie podría definir planes de cuidado).';
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_zz_prevent_profile_deactivation_without_clinico
  on public.profiles;
drop trigger if exists trg_zz_prevent_profile_removes_last_capable
  on public.profiles;
create trigger trg_zz_prevent_profile_removes_last_capable
  before update on public.profiles
  for each row execute function public.prevent_profile_removes_last_capable();

-- Limpieza: las funciones de 0111 ya no las usa ningún trigger (se reemplazaron
-- arriba). Se eliminan para no dejar lógica muerta que confunda.
drop function if exists public.prevent_org_without_clinico();
drop function if exists public.prevent_profile_deactivation_without_clinico();
drop function if exists public.org_has_other_effective_clinico(uuid, uuid);
