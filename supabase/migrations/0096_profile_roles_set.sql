-- =============================================================================
-- 0096_profile_roles_set.sql — Fase A: roles como CONJUNTO (sin cambiar conducta)
-- =============================================================================
-- profiles.role es una sola columna de enum (un rol por persona). El negocio
-- necesita un CONJUNTO ("cuando el clínico hace todo, tiene todos los roles").
-- Fase A: agregar el conjunto y hacer que los helpers lo lean, SIN que nadie
-- note un cambio de capacidad (criterio duro).
--
-- AUTORIDAD = `roles`. `role` (singular) queda como espejo para poder revertir.
-- Como `roles` se deriva de `role` (backfill + trigger), el comportamiento es
-- idéntico al de hoy. En Fase B la app escribirá `roles` directo y este trigger
-- se reemplaza por la sincronización inversa (role = rol primario de roles).
--
-- HALLAZGOS (reportados a Carlos antes de aplicar):
--   - Además de is_admin/is_master/is_nurse, `current_user_role()` (0002:191)
--     lee `role` y se usa en ~12 políticas de 0045/0084
--     (`current_user_role()::text = 'clinico' | in ('clinico','enfermeria')`).
--     Aquí se DEJA como está: `role` sigue siendo el espejo primario, así que
--     esas políticas se comportan igual que hoy. Hacerlas set-aware es Fase B.
--   - La columna nueva abre un hueco de escalada; se extiende el guard de 0006.
-- =============================================================================

-- 1. Columna nueva (arreglo de user_role). Se puebla abajo y por trigger.
alter table public.profiles
  add column if not exists roles public.user_role[] not null default '{}';

-- 2. Backfill que PRESERVA la conducta actual: hoy `admin` ya diagnostica
--    (canDiagnose incluye admin), así que admin → {admin, clinico}. El resto,
--    su propio rol. Idempotente (solo filas sin poblar).
update public.profiles
  set roles = case
    when role = 'admin'::public.user_role
      then array['admin', 'clinico']::public.user_role[]
    else array[role]
  end
  where roles = '{}';

-- 3. Sincronización role → roles (Fase A): cualquier escritura de `role` (app,
--    RPCs como 0011, admin-create-user) mantiene el conjunto correcto SIN tocar
--    la app. FASE B: reemplazar por la sincronización inversa.
create or replace function public.sync_profile_roles()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.role = 'admin'::public.user_role then
    new.roles := array['admin', 'clinico']::public.user_role[];
  else
    new.roles := array[new.role];
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_profile_roles on public.profiles;
create trigger trg_sync_profile_roles
  before insert or update of role on public.profiles
  for each row execute function public.sync_profile_roles();

-- 4. Helpers SET-AWARE. Leen `roles` (autoridad). Como roles ≡ f(role), el
--    resultado booleano es idéntico al de hoy para cada rol.
create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((select 'admin'::public.user_role = any(roles)
                   from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.is_master()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((select 'master'::public.user_role = any(roles)
                   from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.is_nurse()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((select 'enfermeria'::public.user_role = any(roles)
                   from public.profiles where id = auth.uid()), false);
$$;

-- 5. Cierra el hueco de escalada que abre la nueva columna: 0006 solo protegía
--    role/premium_enabled. Sin esto, un no-admin podría auto-asignarse `roles`
--    (la política de UPDATE de profiles no restringe columnas).
create or replace function public.prevent_profile_privilege_escalation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if new.role is distinct from old.role
       or new.roles is distinct from old.roles
       or new.premium_enabled is distinct from old.premium_enabled then
      raise exception 'No autorizado: solo un administrador puede modificar role/roles o premium_enabled';
    end if;
  end if;
  return new;
end;
$$;
