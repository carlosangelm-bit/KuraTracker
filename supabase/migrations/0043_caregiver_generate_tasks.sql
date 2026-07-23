-- =============================================================================
-- 0043_caregiver_generate_tasks.sql — el cuidador puede generar su plan
-- =============================================================================
-- El cuestionario preventivo unificado lo llenan tanto el personal del centro
-- como el CUIDADOR (en sus pacientes asignados), y al confirmarlo se agendan
-- tareas (INSERT en preventive_tasks). La policy ptasks_insert de 0042 solo
-- permitía master / admin de la org / clínico asignado. Se AÑADE la rama del
-- cuidador asignado (is_caregiver_of), de forma aditiva. ptasks_update ya
-- permite al asignado (assignee_profile_id = auth.uid()) marcar hechas/saltar.
-- =============================================================================

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
    or public.is_caregiver_of(patient_id)
  );

-- Para poder REGENERAR el plan (el flujo borra las tareas AUTO futuras
-- pendientes y las recrea), el cuidador también necesita DELETE de las tareas
-- de sus pacientes asignados. Se añade una policy de delete acotada al cuidador
-- asignado (la de 0042 solo permitía master/admin).
drop policy if exists ptasks_delete_caregiver on public.preventive_tasks;
create policy ptasks_delete_caregiver on public.preventive_tasks
  for delete using (public.is_caregiver_of(patient_id));
