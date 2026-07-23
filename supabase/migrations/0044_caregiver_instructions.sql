-- =============================================================================
-- 0044_caregiver_instructions.sql — Indicaciones del profesional para el cuidador
-- =============================================================================
-- En el flujo más frecuente (paciente CON lesión), quien define los cuidados es
-- el PROFESIONAL: además de agendar las tareas, deja un set de INDICACIONES en
-- texto libre para el cuidador según el diagnóstico (p.ej. "limpiar con SF, no
-- mojar el apósito, avisar si hay fiebre"). El cuidador las ve (solo lectura).
-- Una fila por paciente (upsert por patient_id).
-- =============================================================================

create table if not exists public.caregiver_instructions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  instructions text,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (patient_id)
);

create index if not exists idx_caregiver_instructions_org
  on public.caregiver_instructions(organization_id);

alter table public.caregiver_instructions enable row level security;

-- SELECT: personal del centro con acceso al paciente + el cuidador asignado.
drop policy if exists caregiver_instructions_select on public.caregiver_instructions;
create policy caregiver_instructions_select on public.caregiver_instructions
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = caregiver_instructions.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or public.is_caregiver_of(patient_id)
  );

-- INSERT/UPDATE: solo personal del centro (master / admin de la org / clínico
-- asignado). El cuidador NO escribe indicaciones (no prescribe).
drop policy if exists caregiver_instructions_insert on public.caregiver_instructions;
create policy caregiver_instructions_insert on public.caregiver_instructions
  for insert with check (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = caregiver_instructions.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );

drop policy if exists caregiver_instructions_update on public.caregiver_instructions;
create policy caregiver_instructions_update on public.caregiver_instructions
  for update using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = caregiver_instructions.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );

drop policy if exists caregiver_instructions_delete on public.caregiver_instructions;
create policy caregiver_instructions_delete on public.caregiver_instructions
  for delete using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop trigger if exists trg_audit_caregiver_instructions on public.caregiver_instructions;
create trigger trg_audit_caregiver_instructions
  after insert or update or delete on public.caregiver_instructions
  for each row execute function public.audit_trigger_fn();

comment on table public.caregiver_instructions is
  'Indicaciones en texto libre del profesional para el cuidador de un paciente '
  '(Fase 3+). El cuidador las lee; solo el personal del centro las edita.';
