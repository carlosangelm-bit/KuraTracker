-- 0020_manual_scheduling.sql
--
-- Agenda multi-centro, Fase 1: modo de agenda por organización + citas manuales
-- para centros que no usan Acuity.
--
-- Modo por centro (organizations.scheduling_mode):
--   'none'   -> aún no configurada
--   'manual' -> agenda gestionada dentro de KuraTracker (esta tabla)
--   'acuity' -> integración con Acuity Scheduling (tabla appointments + Edge Functions)
-- (Fase 2 agregará credenciales de Acuity por centro; ver README.)

alter table public.organizations
  add column if not exists scheduling_mode text not null default 'none';

comment on column public.organizations.scheduling_mode is
  'Modo de agenda del centro: none | manual | acuity. Determina qué fuente usa '
  'la pantalla Agenda y si el CRUD de citas es local (manual) o vía Acuity.';

-- Los centros que ya tienen Kuradores mapeados a Acuity quedan en modo 'acuity'.
update public.organizations o
  set scheduling_mode = 'acuity'
  where scheduling_mode = 'none'
    and exists (
      select 1 from public.staff s
      where s.organization_id = o.id and s.acuity_calendar_id is not null
    );

-- Citas manuales (independientes de Acuity). A diferencia de public.appointments
-- (espejo de Acuity, solo-lectura para el cliente), ESTA tabla SÍ es escribible
-- desde la app por admin/clínico según RLS.
create table if not exists public.manual_appointments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  staff_id uuid references public.staff(id),        -- Kurador asignado
  patient_id uuid references public.patients(id),   -- paciente (expediente)
  title text,                                       -- tipo/motivo (texto libre)
  datetime timestamptz not null,
  end_time timestamptz,
  notes text,
  status text not null default 'scheduled',         -- scheduled | canceled | completed
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_manual_appointments_org on public.manual_appointments(organization_id);
create index if not exists idx_manual_appointments_staff on public.manual_appointments(staff_id);
create index if not exists idx_manual_appointments_datetime on public.manual_appointments(datetime);

-- RLS: mismo criterio multi-centro que el resto (is_master / is_admin+org /
-- clínico dueño). Aquí el cliente SÍ puede escribir (crear/editar/cancelar).
alter table public.manual_appointments enable row level security;

drop policy if exists manual_appointments_select on public.manual_appointments;
create policy manual_appointments_select on public.manual_appointments
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or (staff_id = public.current_staff_id())
  );

drop policy if exists manual_appointments_insert on public.manual_appointments;
create policy manual_appointments_insert on public.manual_appointments
  for insert with check (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or (staff_id = public.current_staff_id())
  );

drop policy if exists manual_appointments_update on public.manual_appointments;
create policy manual_appointments_update on public.manual_appointments
  for update using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or (staff_id = public.current_staff_id())
  );

drop policy if exists manual_appointments_delete on public.manual_appointments;
create policy manual_appointments_delete on public.manual_appointments
  for delete using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or (staff_id = public.current_staff_id())
  );

comment on table public.manual_appointments is
  'Citas gestionadas manualmente en KuraTracker (centros con scheduling_mode = '
  'manual). Escribible por el cliente (admin del centro / clínico dueño) vía RLS.';
