-- 0023_manual_appointment_fields.sql
--
-- Paridad de la agenda MANUAL con el formulario de Acuity ("Consulta a
-- domicilio"): dirección del tratamiento, contacto que recibe al especialista
-- (nombre/teléfono) y foto de la herida. La identidad del paciente se cubre al
-- seleccionar/crear el paciente en el formulario.

alter table public.manual_appointments
  add column if not exists address text,
  add column if not exists contact_name text,
  add column if not exists contact_phone text,
  add column if not exists photo_path text;

comment on column public.manual_appointments.photo_path is
  'Ruta en el bucket privado intake-photos ({organization_id}/{uuid}.ext) de la '
  'foto de la herida, o un data URL base64 en modo demo local.';

-- Bucket privado para fotos de admisión subidas DESDE LA APP (a diferencia de
-- acuity-intake, que solo escribe el service role). Escribible por admin/clínico
-- del propio centro; la ruta empieza por el organization_id para acotar por RLS.
insert into storage.buckets (id, name, public, file_size_limit)
values ('intake-photos', 'intake-photos', false, 17825792) -- 17 MB
on conflict (id) do nothing;

create policy "intake_photos_select" on storage.objects
  for select using (
    bucket_id = 'intake-photos'
    and (
      public.is_master()
      or (storage.foldername(name))[1] = public.current_organization_id()::text
    )
  );

create policy "intake_photos_insert" on storage.objects
  for insert with check (
    bucket_id = 'intake-photos'
    and (
      public.is_master()
      or (storage.foldername(name))[1] = public.current_organization_id()::text
    )
  );

create policy "intake_photos_delete" on storage.objects
  for delete using (
    bucket_id = 'intake-photos'
    and (
      public.is_master()
      or (storage.foldername(name))[1] = public.current_organization_id()::text
    )
  );
