-- =============================================================================
-- KuraTracker - Storage buckets (evidencia fotografica)
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit)
values ('wound-evidence', 'wound-evidence', false, 17825792) -- 17 MB por archivo
on conflict (id) do nothing;

-- Politicas de storage: mismo criterio que wound_photos (clinico solo ve
-- evidencia de sus pacientes asignados; admin ve todo). El path de cada
-- objeto se organiza como: {wound_id}/{consultation_id}/{filename}.

create policy "wound_evidence_select" on storage.objects
  for select using (
    bucket_id = 'wound-evidence'
    and (
      public.is_admin()
      or exists (
        select 1 from public.wounds w
        join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
        where w.id::text = (storage.foldername(name))[1]
          and spa.staff_id = public.current_staff_id()
      )
    )
  );

create policy "wound_evidence_insert" on storage.objects
  for insert with check (
    bucket_id = 'wound-evidence'
    and (
      public.is_admin()
      or exists (
        select 1 from public.wounds w
        join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
        where w.id::text = (storage.foldername(name))[1]
          and spa.staff_id = public.current_staff_id()
      )
    )
  );

create policy "wound_evidence_delete" on storage.objects
  for delete using (
    bucket_id = 'wound-evidence'
    and (
      public.is_admin()
      or exists (
        select 1 from public.wounds w
        join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
        where w.id::text = (storage.foldername(name))[1]
          and spa.staff_id = public.current_staff_id()
      )
    )
  );
