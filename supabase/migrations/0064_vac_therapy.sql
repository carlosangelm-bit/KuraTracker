-- =============================================================================
-- 0064_vac_therapy.sql — Módulo Terapia VAC (NPWT): registro clínico + bitácora
-- =============================================================================
-- Terapia de presión negativa (VAC). Flujo TRANSVERSAL: se coloca en quirófano,
-- pasa a hospitalización, a veces se cambia el equipo (VAC Ulta → ActiVAC) para
-- egreso a domicilio; toca hospital, clínica de heridas y cuidador.
--
-- Fase 1 (esta migración): episodio de terapia por paciente (equipo, parámetros,
-- ubicación, indicaciones para el cuidador) + bitácora de eventos (colocación,
-- transferencia, cambio de equipo/apósito, ajuste, suspensión, egreso…).
-- Las alarmas/bot/escalamiento a humano son de una fase posterior.
--
-- RLS ADITIVA, mismo patrón que 0048/0052: SELECT por organización/master;
-- escritura por personal (admin o staff) de la propia organización, o master.
-- La bitácora vac_events es append-only (sin UPDATE/DELETE).
-- =============================================================================

create table if not exists public.vac_therapies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  wound_id uuid references public.wounds(id) on delete set null,
  equipment_type text not null default 'vac_ulta', -- vac_ulta | activac | otro
  device_serial text,
  mode text,                        -- continuo | intermitente | instilacion
  target_pressure_mmhg integer,
  instillation boolean not null default false,
  instill_solution text,
  instill_dwell_min integer,
  dressing_type text,               -- granufoam | granufoam_plata | whitefoam | otro
  change_interval_hours integer,
  placed_at timestamptz,
  placed_by uuid references public.profiles(id),
  placed_location text,             -- quirofano | hospital | clinica | domicilio
  current_location text,
  status text not null default 'activa', -- activa | pausada | suspendida | finalizada
  caregiver_instructions text,
  notes text,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_vac_therapies_org
  on public.vac_therapies(organization_id);
create index if not exists idx_vac_therapies_patient
  on public.vac_therapies(patient_id);

create table if not exists public.vac_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  therapy_id uuid not null references public.vac_therapies(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  event_type text not null,         -- colocacion | transferencia | cambio_equipo | cambio_aposito | ajuste | suspension | reinicio | egreso_domicilio | finalizacion | nota
  at timestamptz not null default now(),
  by_profile uuid references public.profiles(id),
  location text,
  detail jsonb not null default '{}'::jsonb,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_vac_events_therapy
  on public.vac_events(therapy_id);
create index if not exists idx_vac_events_org
  on public.vac_events(organization_id);

alter table public.vac_therapies enable row level security;
alter table public.vac_events enable row level security;

-- ---- vac_therapies: SELECT ----
drop policy if exists vac_therapies_select on public.vac_therapies;
create policy vac_therapies_select on public.vac_therapies
  for select using (
    public.is_master()
    or organization_id = public.current_organization_id()
  );

-- ---- vac_therapies: INSERT/UPDATE/DELETE (personal del centro o master) ----
drop policy if exists vac_therapies_insert on public.vac_therapies;
create policy vac_therapies_insert on public.vac_therapies
  for insert with check (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );

drop policy if exists vac_therapies_update on public.vac_therapies;
create policy vac_therapies_update on public.vac_therapies
  for update using (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );

drop policy if exists vac_therapies_delete on public.vac_therapies;
create policy vac_therapies_delete on public.vac_therapies
  for delete using (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );

-- ---- vac_events: SELECT ----
drop policy if exists vac_events_select on public.vac_events;
create policy vac_events_select on public.vac_events
  for select using (
    public.is_master()
    or organization_id = public.current_organization_id()
  );

-- ---- vac_events: INSERT (append-only) ----
drop policy if exists vac_events_insert on public.vac_events;
create policy vac_events_insert on public.vac_events
  for insert with check (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );
