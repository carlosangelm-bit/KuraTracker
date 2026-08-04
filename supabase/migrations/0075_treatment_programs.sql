-- =============================================================================
-- 0075_treatment_programs.sql — Plan de tratamiento MENSUAL (programa)
-- =============================================================================
-- Capa intermedia entre la VALORACIÓN y los seguimientos: a partir del régimen
-- del motor, el especialista arma un plan de ~4 semanas con insumos AGRUPADOS
-- POR PROCEDIMIENTO (cantidad POR SESIÓN), y define la cadencia (días + hora) de
-- las sesiones del mes. Al aceptarlo se detonan las sesiones en la agenda
-- (fase 2) y cada seguimiento se pre-carga con esos insumos (fase 3).
--
-- Tres tablas:
--   1) treatment_programs        — encabezado (paciente/herida/valoración, estado).
--   2) treatment_program_supplies — insumos del plan (cantidad por sesión) →
--      la explosión mensual = cantidad_por_sesión × nº de sesiones (para que
--      atención a cliente reserve stock).
--   3) treatment_program_sessions — las sesiones del mes (fecha+hora), su cita y
--      la consulta de seguimiento cuando se realiza.
--
-- RLS ADITIVA, mismo patrón que point_payments/patient_labs: SELECT por
-- organización/master; escritura por personal (admin o staff) de la propia
-- organización, o master. No toca ninguna policy existente.
-- =============================================================================

-- 1) Encabezado del programa ------------------------------------------------
create table if not exists public.treatment_programs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  wound_id uuid not null references public.wounds(id) on delete cascade,
  consultation_id uuid references public.consultations(id) on delete set null, -- la valoración
  site_id uuid references public.sites(id) on delete set null,
  staff_id uuid references public.staff(id) on delete set null,               -- kurador
  weeks int not null default 4,
  status text not null default 'borrador',  -- borrador | aceptado | cancelado | completado
  notes text,
  accepted_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_tx_programs_org on public.treatment_programs(organization_id);
create index if not exists idx_tx_programs_wound on public.treatment_programs(wound_id);
create index if not exists idx_tx_programs_consult on public.treatment_programs(consultation_id);

-- 2) Insumos del plan (cantidad POR SESIÓN) ---------------------------------
create table if not exists public.treatment_program_supplies (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.treatment_programs(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  method text not null,                 -- procedimiento (p.ej. Desbridamiento)
  product text,                         -- genérico del régimen (p.ej. Autolítico)
  inventory_item_id uuid references public.inventory_items(id) on delete set null,
  name text not null,                   -- nombre del producto concreto
  quantity_per_session numeric(10, 2) not null default 1,
  unit_cost numeric(10, 2),
  unit_price numeric(10, 2),
  currency text default 'MXN',
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_tx_prog_supplies_program
  on public.treatment_program_supplies(program_id);

-- 3) Sesiones del mes (fecha+hora) ------------------------------------------
create table if not exists public.treatment_program_sessions (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.treatment_programs(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  staff_id uuid references public.staff(id) on delete set null,
  scheduled_at timestamptz not null,    -- fecha + hora de la sesión
  end_at timestamptz,
  status text not null default 'planeada', -- planeada | agendada | realizada | cancelada
  appointment_ref text,                 -- liga a la cita: 'acuity:<id>' | 'manual:<uuid>' | 'program:<id>'
  consultation_id uuid references public.consultations(id) on delete set null, -- el seguimiento
  sort_index int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_tx_prog_sessions_program
  on public.treatment_program_sessions(program_id);
create index if not exists idx_tx_prog_sessions_patient
  on public.treatment_program_sessions(patient_id, scheduled_at);
create index if not exists idx_tx_prog_sessions_staff
  on public.treatment_program_sessions(staff_id, scheduled_at);

-- RLS ADITIVA para las tres tablas (patrón point_payments 0055) --------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'treatment_programs',
    'treatment_program_supplies',
    'treatment_program_sessions'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %1$s_select on public.%1$s', t);
    execute format($p$
      create policy %1$s_select on public.%1$s for select using (
        public.is_master() or organization_id = public.current_organization_id()
      )$p$, t);
    execute format('drop policy if exists %1$s_write on public.%1$s', t);
    execute format($p$
      create policy %1$s_write on public.%1$s for all using (
        public.is_master()
        or (organization_id = public.current_organization_id()
            and (public.is_admin() or public.current_staff_id() is not null))
      ) with check (
        public.is_master()
        or (organization_id = public.current_organization_id()
            and (public.is_admin() or public.current_staff_id() is not null))
      )$p$, t);
    execute format('drop trigger if exists trg_audit_%1$s on public.%1$s', t);
    execute format($p$
      create trigger trg_audit_%1$s after insert or update or delete on public.%1$s
      for each row execute function public.audit_trigger_fn()$p$, t);
  end loop;
end $$;

comment on table public.treatment_programs is
  'Plan de tratamiento mensual (programa) derivado de la valoración; se acepta y detona sesiones en la agenda.';
comment on table public.treatment_program_supplies is
  'Insumos del plan por PROCEDIMIENTO, con cantidad POR SESIÓN. La explosión mensual = cantidad_por_sesión × nº de sesiones.';
comment on table public.treatment_program_sessions is
  'Sesiones del mes (fecha+hora) del programa; ligan a su cita y a la consulta de seguimiento.';
