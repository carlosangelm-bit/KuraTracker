-- =============================================================================
-- 0042_preventive_tasks.sql — Agenda de prevención + acceso del cuidador (Fase 3)
-- =============================================================================
-- Dos piezas:
--  (A) preventive_tasks: tareas preventivas AGENDADAS (fecha futura + asignado
--      + estado), autogeneradas desde las reglas (cadencias) y editables. Al
--      marcarlas hechas la app también registra en preventive_action_log (0037)
--      para conservar la bitácora.
--  (B) Acceso del CUIDADOR (rol 'cuidador', creado en 0040): un cuidador NO
--      tiene fila en `staff`, así que HOY current_staff_id() es NULL y NO ve
--      ningún dato clínico (todas las policies clínicas comparan contra
--      staff_patient_assignments + current_staff_id → falso). Aquí se le da
--      acceso de SOLO LECTURA, y SOLO a los pacientes que el centro le asigna
--      explícitamente (caregiver_patient_assignments). Se hace AÑADIENDO
--      policies SELECT adicionales (permisivas ⇒ se combinan con OR), sin tocar
--      las policies existentes: cero riesgo de romper el acceso actual.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Asignación cuidador ↔ paciente (el centro decide qué pacientes monitorea)
-- -----------------------------------------------------------------------------
create table if not exists public.caregiver_patient_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  caregiver_profile_id uuid not null references public.profiles(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  assigned_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (caregiver_profile_id, patient_id)
);

create index if not exists idx_cpa_caregiver on public.caregiver_patient_assignments(caregiver_profile_id);
create index if not exists idx_cpa_patient on public.caregiver_patient_assignments(patient_id);
create index if not exists idx_cpa_org on public.caregiver_patient_assignments(organization_id);

alter table public.caregiver_patient_assignments enable row level security;

-- El cuidador ve SUS asignaciones; admin de la org y master las gestionan.
drop policy if exists cpa_select on public.caregiver_patient_assignments;
create policy cpa_select on public.caregiver_patient_assignments
  for select using (
    caregiver_profile_id = auth.uid()
    or public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop policy if exists cpa_insert on public.caregiver_patient_assignments;
create policy cpa_insert on public.caregiver_patient_assignments
  for insert with check (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop policy if exists cpa_delete on public.caregiver_patient_assignments;
create policy cpa_delete on public.caregiver_patient_assignments
  for delete using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop trigger if exists trg_audit_caregiver_patient_assignments on public.caregiver_patient_assignments;
create trigger trg_audit_caregiver_patient_assignments
  after insert or update or delete on public.caregiver_patient_assignments
  for each row execute function public.audit_trigger_fn();

comment on table public.caregiver_patient_assignments is
  'Vínculo cuidador↔paciente (Fase 3): el centro (admin/master) autoriza a un '
  'usuario cuidador a MONITOREAR (solo lectura) a pacientes concretos. Base del '
  'acceso de lectura del cuidador (ver is_caregiver_of).';

-- -----------------------------------------------------------------------------
-- 2. Helper RLS: is_caregiver_of(patient) — mismo patrón que is_admin/is_master
-- -----------------------------------------------------------------------------
create or replace function public.is_caregiver_of(p_patient uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.caregiver_patient_assignments cpa
    where cpa.patient_id = p_patient
      and cpa.caregiver_profile_id = auth.uid()
  );
$$;

comment on function public.is_caregiver_of(uuid) is
  'true si el usuario autenticado es un cuidador asignado a ese paciente '
  '(caregiver_patient_assignments). Se usa para AÑADIR una rama de SOLO LECTURA '
  'a las policies SELECT clínicas, sin tocar las existentes.';

-- -----------------------------------------------------------------------------
-- 3. Policies SELECT ADICIONALES para el cuidador (solo lectura, aditivas)
-- -----------------------------------------------------------------------------
-- No se toca ninguna policy existente. Cada una concede lectura al cuidador
-- solo para sus pacientes asignados. Anclaje: patients.id directo; tablas
-- descendientes de herida vía wounds.patient_id.

drop policy if exists patients_caregiver_select on public.patients;
create policy patients_caregiver_select on public.patients
  for select using (public.is_caregiver_of(id));

drop policy if exists consultations_caregiver_select on public.consultations;
create policy consultations_caregiver_select on public.consultations
  for select using (public.is_caregiver_of(patient_id));

drop policy if exists wounds_caregiver_select on public.wounds;
create policy wounds_caregiver_select on public.wounds
  for select using (public.is_caregiver_of(patient_id));

drop policy if exists assessments_caregiver_select on public.wound_assessments;
create policy assessments_caregiver_select on public.wound_assessments
  for select using (exists (
    select 1 from public.wounds w
    where w.id = wound_assessments.wound_id and public.is_caregiver_of(w.patient_id)
  ));

drop policy if exists measurements_caregiver_select on public.wound_measurements;
create policy measurements_caregiver_select on public.wound_measurements
  for select using (exists (
    select 1 from public.wounds w
    where w.id = wound_measurements.wound_id and public.is_caregiver_of(w.patient_id)
  ));

drop policy if exists photos_caregiver_select on public.wound_photos;
create policy photos_caregiver_select on public.wound_photos
  for select using (exists (
    select 1 from public.wounds w
    where w.id = wound_photos.wound_id and public.is_caregiver_of(w.patient_id)
  ));

drop policy if exists treatment_plans_caregiver_select on public.treatment_plans;
create policy treatment_plans_caregiver_select on public.treatment_plans
  for select using (exists (
    select 1 from public.wounds w
    where w.id = treatment_plans.wound_id and public.is_caregiver_of(w.patient_id)
  ));

drop policy if exists treatment_components_caregiver_select on public.treatment_components;
create policy treatment_components_caregiver_select on public.treatment_components
  for select using (exists (
    select 1 from public.treatment_plans tp
    join public.wounds w on w.id = tp.wound_id
    where tp.id = treatment_components.treatment_plan_id
      and public.is_caregiver_of(w.patient_id)
  ));

drop policy if exists kura_recommendations_caregiver_select on public.kura_recommendations;
create policy kura_recommendations_caregiver_select on public.kura_recommendations
  for select using (exists (
    select 1 from public.wounds w
    where w.id = kura_recommendations.wound_id and public.is_caregiver_of(w.patient_id)
  ));

drop policy if exists sheehan_caregiver_select on public.sheehan_checkpoints;
create policy sheehan_caregiver_select on public.sheehan_checkpoints
  for select using (exists (
    select 1 from public.wounds w
    where w.id = sheehan_checkpoints.wound_id and public.is_caregiver_of(w.patient_id)
  ));

-- Próxima cita del paciente (manual_appointments lleva patient_id).
drop policy if exists manual_appt_caregiver_select on public.manual_appointments;
create policy manual_appt_caregiver_select on public.manual_appointments
  for select using (public.is_caregiver_of(patient_id));

-- -----------------------------------------------------------------------------
-- 4. preventive_tasks — agenda de tareas preventivas
-- -----------------------------------------------------------------------------
create table if not exists public.preventive_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  admission_id uuid references public.patient_admissions(id) on delete set null,
  rule_id text,
  action_id text,
  title text not null,
  action_label text,
  scheduled_at timestamptz not null,
  assignee_profile_id uuid references public.profiles(id) on delete set null,
  assignee_kind text not null default 'staff',   -- staff | cuidador
  recurrence jsonb,
  status text not null default 'pending',         -- pending | done | skipped | canceled
  done_at timestamptz,
  done_by uuid references public.profiles(id),
  notes text,
  source text not null default 'auto',            -- auto | manual
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint preventive_tasks_status_chk
    check (status in ('pending', 'done', 'skipped', 'canceled')),
  constraint preventive_tasks_assignee_kind_chk
    check (assignee_kind in ('staff', 'cuidador'))
);

create index if not exists idx_ptasks_org on public.preventive_tasks(organization_id);
create index if not exists idx_ptasks_patient on public.preventive_tasks(patient_id);
create index if not exists idx_ptasks_assignee on public.preventive_tasks(assignee_profile_id);
create index if not exists idx_ptasks_scheduled on public.preventive_tasks(scheduled_at);

alter table public.preventive_tasks enable row level security;

-- Predicado reutilizable de "puedo ver/gestionar tareas de este paciente":
-- admin de la org, clínico asignado, cuidador asignado, o master.
-- (Se escribe inline en cada policy por claridad.)

drop policy if exists ptasks_select on public.preventive_tasks;
create policy ptasks_select on public.preventive_tasks
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = preventive_tasks.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or public.is_caregiver_of(patient_id)
    or assignee_profile_id = auth.uid()
  );

-- Crear/generar tareas: master, admin de la org o clínico asignado. El cuidador
-- NO crea tareas (solo ejecuta las suyas).
drop policy if exists ptasks_insert on public.preventive_tasks;
create policy ptasks_insert on public.preventive_tasks
  for insert with check (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = preventive_tasks.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- Actualizar (reprogramar, marcar hecha/saltada): personal del centro asignado
-- + el ASIGNADO de la tarea (para que el cuidador pueda marcar SUS tareas). La
-- app solo expone "marcar hecha/saltar" al cuidador.
drop policy if exists ptasks_update on public.preventive_tasks;
create policy ptasks_update on public.preventive_tasks
  for update using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = preventive_tasks.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or assignee_profile_id = auth.uid()
  );

-- Borrar: solo master o admin de la org.
drop policy if exists ptasks_delete on public.preventive_tasks;
create policy ptasks_delete on public.preventive_tasks
  for delete using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

drop trigger if exists trg_audit_preventive_tasks on public.preventive_tasks;
create trigger trg_audit_preventive_tasks
  after insert or update or delete on public.preventive_tasks
  for each row execute function public.audit_trigger_fn();

comment on table public.preventive_tasks is
  'Tareas preventivas agendadas (Fase 3): fecha + asignado + estado. '
  'Autogeneradas desde prevention_rules.json (cadencias) o creadas manualmente. '
  'El cuidador ve/actualiza solo las suyas; el personal del centro gestiona las '
  'de sus pacientes. Marcar hecha también registra en preventive_action_log.';
