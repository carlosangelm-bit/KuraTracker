-- =============================================================================
-- KuraTracker - Row Level Security (RLS)
-- =============================================================================
-- Modelo de acceso:
--   admin   -> acceso total de lectura/escritura a todas las tablas clinicas.
--   clinico -> solo puede ver/editar pacientes que tiene asignados
--              (staff_patient_assignments), y solo puede crear/editar
--              consultas, evaluaciones, mediciones, fotos, tratamientos y
--              recomendaciones para esos pacientes.
-- Todas las tablas con datos clinicos tienen RLS habilitado (requisito de
-- seguridad, seccion 2).
-- =============================================================================

alter table public.profiles enable row level security;
alter table public.sites enable row level security;
alter table public.staff enable row level security;
alter table public.staff_patient_assignments enable row level security;
alter table public.patients enable row level security;
alter table public.patient_comorbidities enable row level security;
alter table public.consultations enable row level security;
alter table public.wounds enable row level security;
alter table public.wound_assessments enable row level security;
alter table public.wound_measurements enable row level security;
alter table public.perfusion_nutrition_data enable row level security;
alter table public.wound_photos enable row level security;
alter table public.treatment_plans enable row level security;
alter table public.treatment_components enable row level security;
alter table public.kura_recommendations enable row level security;
alter table public.sheehan_checkpoints enable row level security;
alter table public.audit_log enable row level security;
alter table public.import_batches enable row level security;

-- -----------------------------------------------------------------------------
-- PROFILES
-- -----------------------------------------------------------------------------
create policy profiles_select_own_or_admin on public.profiles
  for select using (id = auth.uid() or public.is_admin());
create policy profiles_update_own_or_admin on public.profiles
  for update using (id = auth.uid() or public.is_admin());
create policy profiles_admin_insert on public.profiles
  for insert with check (public.is_admin() or id = auth.uid());
create policy profiles_admin_delete on public.profiles
  for delete using (public.is_admin());

-- -----------------------------------------------------------------------------
-- SITES (catalogo visible para todo usuario autenticado; solo admin escribe)
-- -----------------------------------------------------------------------------
create policy sites_select_all on public.sites
  for select using (auth.uid() is not null);
create policy sites_admin_write on public.sites
  for insert with check (public.is_admin());
create policy sites_admin_update on public.sites
  for update using (public.is_admin());
create policy sites_admin_delete on public.sites
  for delete using (public.is_admin());

-- -----------------------------------------------------------------------------
-- STAFF
-- -----------------------------------------------------------------------------
create policy staff_select_self_or_admin on public.staff
  for select using (profile_id = auth.uid() or public.is_admin());
create policy staff_admin_insert on public.staff
  for insert with check (public.is_admin());
create policy staff_admin_update on public.staff
  for update using (public.is_admin());
create policy staff_admin_delete on public.staff
  for delete using (public.is_admin());

-- -----------------------------------------------------------------------------
-- STAFF_PATIENT_ASSIGNMENTS
-- -----------------------------------------------------------------------------
create policy assignments_select on public.staff_patient_assignments
  for select using (
    public.is_admin() or staff_id = public.current_staff_id()
  );
create policy assignments_admin_write on public.staff_patient_assignments
  for insert with check (public.is_admin());
create policy assignments_admin_delete on public.staff_patient_assignments
  for delete using (public.is_admin());

-- -----------------------------------------------------------------------------
-- PATIENTS
-- Un clinico solo ve pacientes que tiene asignados; admin ve todos.
-- -----------------------------------------------------------------------------
create policy patients_select on public.patients
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patients.id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy patients_insert on public.patients
  for insert with check (public.is_admin() or public.current_staff_id() is not null);
create policy patients_update on public.patients
  for update using (
    public.is_admin()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patients.id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy patients_admin_delete on public.patients
  for delete using (public.is_admin());

-- -----------------------------------------------------------------------------
-- PATIENT_COMORBIDITIES (hereda visibilidad del paciente)
-- -----------------------------------------------------------------------------
create policy comorbidities_select on public.patient_comorbidities
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patient_comorbidities.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy comorbidities_write on public.patient_comorbidities
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patient_comorbidities.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- CONSULTATIONS
-- -----------------------------------------------------------------------------
create policy consultations_select on public.consultations
  for select using (
    public.is_admin()
    or staff_id = public.current_staff_id()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = consultations.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy consultations_write on public.consultations
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = consultations.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- WOUNDS
-- -----------------------------------------------------------------------------
create policy wounds_select on public.wounds
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = wounds.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy wounds_write on public.wounds
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = wounds.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- WOUND_ASSESSMENTS (hereda de wounds via wound_id)
-- -----------------------------------------------------------------------------
create policy assessments_select on public.wound_assessments
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_assessments.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy assessments_write on public.wound_assessments
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_assessments.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- WOUND_MEASUREMENTS
-- -----------------------------------------------------------------------------
create policy measurements_select on public.wound_measurements
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_measurements.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy measurements_write on public.wound_measurements
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_measurements.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- PERFUSION_NUTRITION_DATA
-- -----------------------------------------------------------------------------
create policy perfusion_select on public.perfusion_nutrition_data
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = perfusion_nutrition_data.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy perfusion_write on public.perfusion_nutrition_data
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = perfusion_nutrition_data.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- WOUND_PHOTOS
-- -----------------------------------------------------------------------------
create policy photos_select on public.wound_photos
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_photos.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy photos_write on public.wound_photos
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_photos.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- TREATMENT_PLANS / TREATMENT_COMPONENTS
-- -----------------------------------------------------------------------------
create policy treatment_plans_select on public.treatment_plans
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = treatment_plans.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy treatment_plans_write on public.treatment_plans
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = treatment_plans.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );

create policy treatment_components_select on public.treatment_components
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.treatment_plans tp
      join public.wounds w on w.id = tp.wound_id
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where tp.id = treatment_components.treatment_plan_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy treatment_components_write on public.treatment_components
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.treatment_plans tp
      join public.wounds w on w.id = tp.wound_id
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where tp.id = treatment_components.treatment_plan_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- KURA_RECOMMENDATIONS
-- -----------------------------------------------------------------------------
create policy recommendations_select on public.kura_recommendations
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = kura_recommendations.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy recommendations_write on public.kura_recommendations
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = kura_recommendations.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- SHEEHAN_CHECKPOINTS
-- -----------------------------------------------------------------------------
create policy sheehan_select on public.sheehan_checkpoints
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = sheehan_checkpoints.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy sheehan_write on public.sheehan_checkpoints
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = sheehan_checkpoints.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- -----------------------------------------------------------------------------
-- AUDIT_LOG (solo admin puede leer; nadie escribe directamente, solo triggers)
-- -----------------------------------------------------------------------------
create policy audit_log_admin_select on public.audit_log
  for select using (public.is_admin());

-- -----------------------------------------------------------------------------
-- IMPORT_BATCHES (solo admin)
-- -----------------------------------------------------------------------------
create policy import_batches_admin on public.import_batches
  for all using (public.is_admin());
