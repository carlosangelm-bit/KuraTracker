-- =============================================================================
-- 0098_roles_set_phaseB.sql — Roles como conjunto, FASE B (base de datos)
-- =============================================================================
-- Fase A (0096) agregó `profiles.roles` y los helpers is_admin/is_master/is_nurse
-- leen el conjunto (roles ≡ f(role), conducta preservada). Fase B hace que el
-- CONJUNTO gobierne de verdad, y prepara a la app para escribir `roles` directo.
--
-- Aquí van las DOS MINAS anotadas en 0096:
--   MINA 1 (trigger): el trigger role→roles de 0096 machaca en silencio cualquier
--     escritura directa de `roles`. Se reemplaza por uno BIDIRECCIONAL: si cambia
--     `roles`, es la autoridad → deriva el espejo `role`; si un writer legacy toca
--     solo `role`, deriva `roles` (compat con RPC 0011 y admin-create-user).
--   MINA 2 (current_user_role): devuelve un valor ÚNICO, no set-aware. Sus ~23
--     políticas (0045/0084) están escritas en la BD (varias con execute format);
--     se DROP + recrean con el predicado `has_role()`.
--
-- NO se toca `consultations_write` ni otras policies vigentes ajenas a esto. El
-- espejo `role` y la función current_user_role() se CONSERVAN (revert / auditoría
-- 0002:108); dropear la columna `role` es un paso posterior.
-- =============================================================================

-- 1. Helpers de conjunto.
create or replace function public.has_role(r public.user_role)
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((select r = any(roles) from public.profiles where id = auth.uid()), false);
$$;

-- Rol "primario" del conjunto (para el espejo `role`, por precedencia).
create or replace function public.primary_role(rs public.user_role[])
returns public.user_role language sql immutable
set search_path = public, pg_temp
as $$
  select case
    when 'master'::public.user_role = any(rs) then 'master'::public.user_role
    when 'admin'::public.user_role = any(rs) then 'admin'::public.user_role
    when 'clinico'::public.user_role = any(rs) then 'clinico'::public.user_role
    when 'enfermeria'::public.user_role = any(rs) then 'enfermeria'::public.user_role
    when 'cuidador'::public.user_role = any(rs) then 'cuidador'::public.user_role
    else null
  end;
$$;

-- 2. MINA 1 — trigger BIDIRECCIONAL (reemplaza el role→roles de 0096).
create or replace function public.sync_profile_roles()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.roles is null or new.roles = '{}' then
      -- Alta legacy que solo trae `role` → deriva `roles`.
      new.roles := case when new.role = 'admin'::public.user_role
                        then array['admin', 'clinico']::public.user_role[]
                        else array[new.role] end;
    else
      -- Alta con `roles` (Fase B) → deriva el espejo `role`.
      new.role := public.primary_role(new.roles);
    end if;
  else -- UPDATE
    if new.roles is distinct from old.roles then
      new.role := public.primary_role(new.roles);   -- roles es la autoridad
    elsif new.role is distinct from old.role then
      new.roles := case when new.role = 'admin'::public.user_role
                        then array['admin', 'clinico']::public.user_role[]
                        else array[new.role] end;    -- writer legacy tocó role
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_profile_roles on public.profiles;
create trigger trg_sync_profile_roles
  before insert or update of role, roles on public.profiles
  for each row execute function public.sync_profile_roles();

-- 3. MINA 2 — recrear las políticas de current_user_role con has_role().
-- Grupo A (write diagnóstico/protocolo, solo clínico) en hospital.
drop policy if exists patients_hospital_write on public.patients;
create policy patients_hospital_write on public.patients
  for all
  using (public.has_hospital_org_access(id) and public.has_role('clinico'::public.user_role))
  with check (public.has_hospital_org_access(id) and public.has_role('clinico'::public.user_role));

do $$
declare tbl text;
begin
  foreach tbl in array array['wounds','consultations','patient_diagnoses','patient_comorbidities'] loop
    execute format('drop policy if exists %I on public.%I', tbl||'_hospital_write', tbl);
    execute format(
      'create policy %I on public.%I for all using (public.has_hospital_org_access(patient_id) and public.has_role(%L::public.user_role)) with check (public.has_hospital_org_access(patient_id) and public.has_role(%L::public.user_role))',
      tbl||'_hospital_write', tbl, 'clinico', 'clinico');
  end loop;
end $$;

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
      'create policy %I on public.%I for all using (exists (select 1 from public.wounds w where w.id = %I.wound_id and public.has_hospital_org_access(w.patient_id)) and public.has_role(%L::public.user_role)) with check (exists (select 1 from public.wounds w where w.id = %I.wound_id and public.has_hospital_org_access(w.patient_id)) and public.has_role(%L::public.user_role))',
      tbl||'_hospital_write', tbl, tbl, 'clinico', tbl, 'clinico');
  end loop;
end $$;

drop policy if exists treatment_components_hospital_write on public.treatment_components;
create policy treatment_components_hospital_write on public.treatment_components
  for all
  using (exists (
    select 1 from public.treatment_plans tp join public.wounds w on w.id = tp.wound_id
    where tp.id = treatment_components.treatment_plan_id
      and public.has_hospital_org_access(w.patient_id)) and public.has_role('clinico'::public.user_role))
  with check (exists (
    select 1 from public.treatment_plans tp join public.wounds w on w.id = tp.wound_id
    where tp.id = treatment_components.treatment_plan_id
      and public.has_hospital_org_access(w.patient_id)) and public.has_role('clinico'::public.user_role));

-- Grupo B (reporte/ejecución, clínico Y enfermería).
do $$
declare tbl text;
begin
  foreach tbl in array array['adverse_events','risk_assessments','patient_admissions','preventive_action_log','preventive_tasks'] loop
    execute format('drop policy if exists %I on public.%I', tbl||'_hospital_report_insert', tbl);
    execute format(
      'create policy %I on public.%I for insert with check (public.has_hospital_org_access(patient_id) and (public.has_role(%L::public.user_role) or public.has_role(%L::public.user_role)))',
      tbl||'_hospital_report_insert', tbl, 'clinico', 'enfermeria');
  end loop;
  foreach tbl in array array['adverse_events','risk_assessments','patient_admissions','preventive_tasks'] loop
    execute format('drop policy if exists %I on public.%I', tbl||'_hospital_report_update', tbl);
    execute format(
      'create policy %I on public.%I for update using (public.has_hospital_org_access(patient_id) and (public.has_role(%L::public.user_role) or public.has_role(%L::public.user_role)))',
      tbl||'_hospital_report_update', tbl, 'clinico', 'enfermeria');
  end loop;
end $$;

-- 0084: scale_assessments insert (clínico y enfermería).
drop policy if exists scale_assessments_hospital_insert on public.scale_assessments;
create policy scale_assessments_hospital_insert on public.scale_assessments
  for insert with check (
    public.has_hospital_org_access(patient_id)
    and (public.has_role('clinico'::public.user_role) or public.has_role('enfermeria'::public.user_role))
  );

-- is_nurse (0096) ya lee roles; current_user_role() se conserva (auditoría),
-- pero ya NO decide en ninguna política.
