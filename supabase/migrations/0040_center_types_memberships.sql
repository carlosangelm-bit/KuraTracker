-- =============================================================================
-- 0040_center_types_memberships.sql — Tipos de centro + multi-centro (Fase 1)
-- =============================================================================
-- Contexto: KuraTracker era de un solo "sabor" (clínica de heridas). Se abren
-- TRES tipos de centro (clinica_heridas | hospital | cuidadores) y se habilita
-- que un usuario pertenezca a VARIOS centros y alterne el centro ACTIVO desde
-- el ícono de apósitos. Para NO reescribir toda la RLS clínica existente, se
-- conserva current_organization_id() = profiles.organization_id como "centro
-- activo"; una tabla de membresías lista a qué centros puede entrar cada
-- usuario y con qué rol, y un RPC hace el cambio de centro validando membresía.
--
-- Gotcha de Postgres (ver 0012): "alter type ... add value" va SOLO y PRIMERO.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Enum: nuevo rol 'cuidador' (debe ir solo, antes de cualquier uso)
-- -----------------------------------------------------------------------------
-- El rol 'cuidador' se introduce aquí para que el enum exista desde ya; sus
-- límites de acceso (RLS mínima: solo sus tareas) se afinan en la Fase 3
-- (0042_preventive_tasks). En esta fase no se le concede ningún acceso nuevo.
alter type public.user_role add value if not exists 'cuidador';

-- -----------------------------------------------------------------------------
-- 1. organizations.center_type
-- -----------------------------------------------------------------------------
alter table public.organizations
  add column if not exists center_type text not null default 'clinica_heridas';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'organizations_center_type_chk'
  ) then
    alter table public.organizations
      add constraint organizations_center_type_chk
      check (center_type in ('clinica_heridas', 'hospital', 'cuidadores'));
  end if;
end $$;

comment on column public.organizations.center_type is
  'Tipo de centro: clinica_heridas (morado, tratamiento) | hospital (azul) | '
  'cuidadores (rosa). Determina la paleta y los módulos por defecto. El módulo '
  'de Prevención NO aplica a clinica_heridas; sí a hospital y cuidadores.';

-- -----------------------------------------------------------------------------
-- 2. user_center_memberships — a qué centros puede entrar cada usuario
-- -----------------------------------------------------------------------------
create table if not exists public.user_center_memberships (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  role public.user_role not null default 'clinico',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (profile_id, organization_id)
);

create index if not exists idx_ucm_profile on public.user_center_memberships(profile_id);
create index if not exists idx_ucm_org on public.user_center_memberships(organization_id);

alter table public.user_center_memberships enable row level security;

-- SELECT: el usuario ve SUS membresías; master todas; admin las de su org.
drop policy if exists ucm_select on public.user_center_memberships;
create policy ucm_select on public.user_center_memberships
  for select using (
    profile_id = auth.uid()
    or public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

-- INSERT/UPDATE/DELETE: solo master o admin de la org. Un usuario normal NO
-- puede crearse membresías (esa es la garantía de seguridad del switch: solo
-- puede cambiarse a centros/roles que un admin/master le concedió).
drop policy if exists ucm_insert on public.user_center_memberships;
create policy ucm_insert on public.user_center_memberships
  for insert with check (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop policy if exists ucm_update on public.user_center_memberships;
create policy ucm_update on public.user_center_memberships
  for update using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop policy if exists ucm_delete on public.user_center_memberships;
create policy ucm_delete on public.user_center_memberships
  for delete using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop trigger if exists trg_audit_user_center_memberships on public.user_center_memberships;
create trigger trg_audit_user_center_memberships
  after insert or update or delete on public.user_center_memberships
  for each row execute function public.audit_trigger_fn();

comment on table public.user_center_memberships is
  'Membresías usuario↔centro: define a qué centros puede entrar un usuario y '
  'con qué rol en cada uno. El centro ACTIVO sigue viviendo en '
  'profiles.organization_id; esta tabla es la lista de opciones del switcher. '
  'Solo admin/master pueden crear membresías.';

-- -----------------------------------------------------------------------------
-- 3. Backfill: una membresía por cada profile con organización vigente
-- -----------------------------------------------------------------------------
-- Preserva el acceso actual: cada usuario queda con membresía a su org actual
-- y su rol actual. Los master (organization_id null) se excluyen: son
-- cross-centro por diseño y no necesitan membresía.
insert into public.user_center_memberships (profile_id, organization_id, role)
select p.id, p.organization_id, p.role
from public.profiles p
where p.organization_id is not null
on conflict (profile_id, organization_id) do nothing;

-- -----------------------------------------------------------------------------
-- 4. Trigger anti-escalada (0006/0012): permitir el SWITCH de centro y cerrar
--    el cambio libre de organization_id
-- -----------------------------------------------------------------------------
-- Antes: el trigger solo bloqueaba cambios de role/premium_enabled para un
-- usuario normal; NO guardaba organization_id, así que un clínico podía
-- apuntar su organization_id a CUALQUIER centro vía PostgREST y ver sus
-- pacientes (current_organization_id() = profiles.organization_id). Ahora un
-- usuario normal solo puede cambiar (organization_id, role) a una combinación
-- que corresponda a una membresía ACTIVA propia — que solo admin/master pueden
-- crear. Esto habilita el switch legítimo y cierra el hueco. premium_enabled
-- sigue reservado a admin/master. admin y master quedan exentos (gestionan
-- centros).
create or replace function public.prevent_profile_privilege_escalation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null and not public.is_admin() and not public.is_master() then
    if new.premium_enabled is distinct from old.premium_enabled then
      raise exception 'No autorizado: solo un administrador puede modificar premium_enabled';
    end if;
    if (new.role is distinct from old.role)
       or (new.organization_id is distinct from old.organization_id) then
      if not exists (
        select 1 from public.user_center_memberships m
        where m.profile_id = new.id
          and m.organization_id = new.organization_id
          and m.role = new.role
          and m.is_active = true
      ) then
        raise exception 'No autorizado: cambio de centro/rol sin membresía válida';
      end if;
    end if;
  end if;
  return new;
end;
$$;

-- El trigger ya existe (0006/0012); create or replace de la función basta.
drop trigger if exists trg_prevent_profile_privilege_escalation on public.profiles;
create trigger trg_prevent_profile_privilege_escalation
  before update on public.profiles
  for each row execute function public.prevent_profile_privilege_escalation();

-- -----------------------------------------------------------------------------
-- 5. RPC set_active_center — cambia el centro activo validando membresía
-- -----------------------------------------------------------------------------
create or replace function public.set_active_center(target_org uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role public.user_role;
begin
  select role into v_role
  from public.user_center_memberships
  where profile_id = auth.uid()
    and organization_id = target_org
    and is_active = true;

  if v_role is null then
    raise exception 'No autorizado: sin membresía activa en el centro %', target_org;
  end if;

  update public.profiles
  set organization_id = target_org,
      role = v_role
  where id = auth.uid();
end;
$$;

comment on function public.set_active_center(uuid) is
  'Cambia el centro ACTIVO del usuario autenticado (profiles.organization_id + '
  'role) a un centro donde tenga membresía activa. Lo usa el switcher del ícono '
  'de apósitos. El trigger anti-escalada permite este cambio precisamente '
  'porque corresponde a una membresía válida.';

grant execute on function public.set_active_center(uuid) to authenticated;
