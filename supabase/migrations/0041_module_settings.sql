-- =============================================================================
-- 0041_module_settings.sql — Módulos configurables por centro/sitio/usuario (Fase 2)
-- =============================================================================
-- Contexto: cada tipo de centro (0040) trae módulos por defecto, pero el master
-- (y el admin de la org) puede personalizar qué módulos ve un centro, un sitio
-- o un usuario concreto. Esta tabla guarda SOLO los overrides; cuando no hay
-- fila, el "encendido efectivo" se deriva del default por tipo de centro
-- (resuelto en la app: usuario > sitio > centro > default-por-tipo).
--
-- Apagar un módulo SOLO lo oculta del menú/rutas; los datos permanecen intactos
-- y reaparecen al reactivarlo (decisión de producto).
--
-- module_key ∈ {patients, agenda, prevention, reports, ekare}. dashboard va
-- siempre encendido; admin/platform se siguen gateando por rol (0012), no aquí.
-- =============================================================================

create table if not exists public.module_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Alcance del override: ambos null = nivel CENTRO; site_id set = nivel SITIO;
  -- profile_id set = nivel USUARIO. (No se mezclan sitio y usuario en la misma
  -- fila; la app escribe uno u otro.)
  site_id uuid references public.sites(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete cascade,
  module_key text not null,
  enabled boolean not null default true,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint module_settings_key_chk
    check (module_key in ('patients', 'agenda', 'prevention', 'reports', 'ekare'))
);

-- Unicidad por alcance: a lo sumo un override por (org, sitio, usuario, módulo).
-- Se usan índices únicos parciales porque site_id/profile_id son nullable y
-- NULL no participa en un unique compuesto normal.
create unique index if not exists uq_module_settings_center
  on public.module_settings(organization_id, module_key)
  where site_id is null and profile_id is null;
create unique index if not exists uq_module_settings_site
  on public.module_settings(organization_id, site_id, module_key)
  where site_id is not null;
create unique index if not exists uq_module_settings_user
  on public.module_settings(organization_id, profile_id, module_key)
  where profile_id is not null;

create index if not exists idx_module_settings_org on public.module_settings(organization_id);

alter table public.module_settings enable row level security;

-- SELECT: cualquier miembro del centro (para que el nav se compute en cliente);
-- master ve todos.
drop policy if exists module_settings_select on public.module_settings;
create policy module_settings_select on public.module_settings
  for select using (
    organization_id = public.current_organization_id()
    or public.is_master()
  );

-- INSERT/UPDATE/DELETE: master o admin de la org.
drop policy if exists module_settings_insert on public.module_settings;
create policy module_settings_insert on public.module_settings
  for insert with check (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop policy if exists module_settings_update on public.module_settings;
create policy module_settings_update on public.module_settings
  for update using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop policy if exists module_settings_delete on public.module_settings;
create policy module_settings_delete on public.module_settings
  for delete using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop trigger if exists trg_audit_module_settings on public.module_settings;
create trigger trg_audit_module_settings
  after insert or update or delete on public.module_settings
  for each row execute function public.audit_trigger_fn();

comment on table public.module_settings is
  'Overrides de habilitación de módulos por centro/sitio/usuario (Fase 2). Sin '
  'fila = default por tipo de centro. Resolución efectiva en la app: usuario > '
  'sitio > centro > default-por-tipo. Apagar solo oculta; los datos permanecen.';
