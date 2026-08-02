-- =============================================================================
-- 0065_vac_settings.sql — Ajustes del módulo VAC por centro (guardia)
-- =============================================================================
-- Fase 2 (alarmas): el escalamiento de una alarma abre WhatsApp hacia la GUARDIA
-- VAC. El número se configura por centro aquí (una fila por organización).
-- RLS ADITIVA, mismo patrón: SELECT por org/master; escritura por personal del
-- centro (admin o staff) de la propia organización, o master.
-- =============================================================================

create table if not exists public.vac_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  oncall_phone text,          -- número de guardia (con lada, para wa.me)
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (organization_id)
);

create index if not exists idx_vac_settings_org
  on public.vac_settings(organization_id);

alter table public.vac_settings enable row level security;

drop policy if exists vac_settings_select on public.vac_settings;
create policy vac_settings_select on public.vac_settings
  for select using (
    public.is_master()
    or organization_id = public.current_organization_id()
  );

drop policy if exists vac_settings_insert on public.vac_settings;
create policy vac_settings_insert on public.vac_settings
  for insert with check (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );

drop policy if exists vac_settings_update on public.vac_settings;
create policy vac_settings_update on public.vac_settings
  for update using (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );
