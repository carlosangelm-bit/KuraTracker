-- =============================================================================
-- 0045_nurse_role_hospital_access.sql — Rol enfermería + acceso hospital
--                                        centrado en el paciente
-- =============================================================================
-- En hospitales el eje es el PACIENTE (turnos/rotación): cualquier personal
-- ACTIVO del centro debe ver a todos los pacientes del centro, y las tareas
-- siguen al paciente. Se añade el rol 'enfermeria' (observa/reporta/ejecuta,
-- NO diagnostica ni cambia protocolo) y acceso centrado-en-centro para
-- centros center_type='hospital'.
--
-- ESTRATEGIA: todo es ADITIVO (nuevas policies permisivas que se combinan con
-- OR), sin tocar las policies existentes → cero riesgo para clínica de heridas
-- y cuidadores (has_hospital_org_access = false ahí).
--
-- Gotcha Postgres: "alter type add value" va PRIMERO y solo. Para NO usar el
-- nuevo valor de enum como literal en la misma transacción, todas las
-- comparaciones de rol usan `current_user_role()::text = '...'` (texto), no el
-- literal de enum.
-- =============================================================================

alter type public.user_role add value if not exists 'enfermeria';

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function public.is_nurse()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select current_user_role()::text = 'enfermeria'), false);
$$;

-- true si el paciente pertenece a un centro HOSPITAL y el llamador tiene una
-- fila de staff ACTIVA en ese mismo centro (acceso centrado-en-centro, sin
-- necesidad de asignación 1:1).
create or replace function public.has_hospital_org_access(p_patient uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.patients pt
    join public.organizations o on o.id = pt.organization_id
    join public.staff s on s.organization_id = pt.organization_id
    where pt.id = p_patient
      and o.center_type = 'hospital'
      and s.profile_id = auth.uid()
      and s.is_active
  );
$$;

comment on function public.has_hospital_org_access(uuid) is
  'true si el paciente está en un centro tipo hospital y el llamador es staff '
  'activo de ese centro. Base del acceso centrado-en-paciente del hospital '
  '(cualquier profesional de turno ve a todos los pacientes del centro).';

-- =============================================================================
-- 1) LECTURA centrada en el centro (hospital): policies SELECT ADITIVAS.
-- =============================================================================
-- patients + tablas con patient_id directo.
drop policy if exists patients_hospital_select on public.patients;
create policy patients_hospital_select on public.patients
  for select using (public.has_hospital_org_access(id));

do $$
declare tbl text;
begin
  foreach tbl in array array[
    'wounds','consultations','patient_diagnoses','patient_comorbidities',
    'adverse_events','risk_assessments','patient_admissions',
    'preventive_action_log','preventive_tasks'
  ] loop
    execute format('drop policy if exists %I on public.%I', tbl||'_hospital_select', tbl);
    execute format(
      'create policy %I on public.%I for select using (public.has_hospital_org_access(patient_id))',
      tbl||'_hospital_select', tbl);
  end loop;
end $$;

-- Descendientes de herida (anclan vía wounds.patient_id).
do $$
declare tbl text;
begin
  foreach tbl in array array[
    'wound_assessments','wound_measurements','wound_photos',
    'perfusion_nutrition_data','treatment_plans','kura_recommendations',
    'sheehan_checkpoints'
  ] loop
    execute format('drop policy if exists %I on public.%I', tbl||'_hospital_select', tbl);
    execute format(
      'create policy %I on public.%I for select using (exists (select 1 from public.wounds w where w.id = %I.wound_id and public.has_hospital_org_access(w.patient_id)))',
      tbl||'_hospital_select', tbl, tbl);
  end loop;
end $$;

-- treatment_components (vía treatment_plan_id -> wound -> patient).
drop policy if exists treatment_components_hospital_select on public.treatment_components;
create policy treatment_components_hospital_select on public.treatment_components
  for select using (exists (
    select 1 from public.treatment_plans tp
    join public.wounds w on w.id = tp.wound_id
    where tp.id = treatment_components.treatment_plan_id
      and public.has_hospital_org_access(w.patient_id)
  ));

-- =============================================================================
-- 2) ESCRITURA de DIAGNÓSTICO/PROTOCOLO (Grupo A) center-wide para CLÍNICO en
--    hospital (nunca enfermería). Policies ADITIVAS FOR ALL (using + with check).
-- =============================================================================
-- patients (using id).
drop policy if exists patients_hospital_write on public.patients;
create policy patients_hospital_write on public.patients
  for all
  using (public.has_hospital_org_access(id) and public.current_user_role()::text = 'clinico')
  with check (public.has_hospital_org_access(id) and public.current_user_role()::text = 'clinico');

do $$
declare tbl text;
begin
  foreach tbl in array array['wounds','consultations','patient_diagnoses','patient_comorbidities'] loop
    execute format('drop policy if exists %I on public.%I', tbl||'_hospital_write', tbl);
    execute format(
      'create policy %I on public.%I for all using (public.has_hospital_org_access(patient_id) and public.current_user_role()::text = %L) with check (public.has_hospital_org_access(patient_id) and public.current_user_role()::text = %L)',
      tbl||'_hospital_write', tbl, 'clinico', 'clinico');
  end loop;
end $$;

-- Descendientes de herida (vía wounds.patient_id).
do $$
declare tbl text;
begin
  foreach tbl in array array[
    'wound_assessments','wound_measurements','wound_photos',
    'perfusion_nutrition_data','treatment_plans','kura_recommendations',
    'sheehan_checkpoints'
  ] loop
    execute format('drop policy if exists %I on public.%I', tbl||'_hospital_write', tbl);
    execute format(
      'create policy %I on public.%I for all using (exists (select 1 from public.wounds w where w.id = %I.wound_id and public.has_hospital_org_access(w.patient_id)) and public.current_user_role()::text = %L) with check (exists (select 1 from public.wounds w where w.id = %I.wound_id and public.has_hospital_org_access(w.patient_id)) and public.current_user_role()::text = %L)',
      tbl||'_hospital_write', tbl, tbl, 'clinico', tbl, 'clinico');
  end loop;
end $$;

drop policy if exists treatment_components_hospital_write on public.treatment_components;
create policy treatment_components_hospital_write on public.treatment_components
  for all
  using (exists (
    select 1 from public.treatment_plans tp join public.wounds w on w.id = tp.wound_id
    where tp.id = treatment_components.treatment_plan_id
      and public.has_hospital_org_access(w.patient_id)) and public.current_user_role()::text = 'clinico')
  with check (exists (
    select 1 from public.treatment_plans tp join public.wounds w on w.id = tp.wound_id
    where tp.id = treatment_components.treatment_plan_id
      and public.has_hospital_org_access(w.patient_id)) and public.current_user_role()::text = 'clinico');

-- =============================================================================
-- 3) ESCRITURA de REPORTE/EJECUCIÓN (Grupo B) center-wide para CLÍNICO Y
--    ENFERMERÍA en hospital. INSERT (todas) + UPDATE (donde aplica).
-- =============================================================================
do $$
declare tbl text;
begin
  -- INSERT para las cuatro tablas de reporte/ejecución.
  foreach tbl in array array['adverse_events','risk_assessments','patient_admissions','preventive_action_log','preventive_tasks'] loop
    execute format('drop policy if exists %I on public.%I', tbl||'_hospital_report_insert', tbl);
    execute format(
      'create policy %I on public.%I for insert with check (public.has_hospital_org_access(patient_id) and public.current_user_role()::text in (%L, %L))',
      tbl||'_hospital_report_insert', tbl, 'clinico', 'enfermeria');
  end loop;
  -- UPDATE donde tiene sentido (no en preventive_action_log: append-only).
  foreach tbl in array array['adverse_events','risk_assessments','patient_admissions','preventive_tasks'] loop
    execute format('drop policy if exists %I on public.%I', tbl||'_hospital_report_update', tbl);
    execute format(
      'create policy %I on public.%I for update using (public.has_hospital_org_access(patient_id) and public.current_user_role()::text in (%L, %L))',
      tbl||'_hospital_report_update', tbl, 'clinico', 'enfermeria');
  end loop;
end $$;

-- NOTA: a enfermería NO se le crean filas en staff_patient_assignments (evita
-- que herede la rama "clínico asignado" de escritura del Grupo A). Su acceso es
-- exclusivamente centrado-en-centro (hospital) y de reporte/ejecución.
