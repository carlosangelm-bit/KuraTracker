-- 0019_acuity_intake_photos.sql
--
-- Almacenamiento DURABLE de la "foto de la herida" del formulario de admisión
-- de Acuity. Hoy la foto vive como URL firmada de S3 dentro de background_notes
-- y esas URLs CADUCAN. Aquí se crea un bucket propio para descargarlas (vía
-- Edge Function, comprimidas) y una columna para la ruta guardada.
--
-- Nota: NO se usa el bucket wound-evidence ni la tabla wound_photos porque la
-- foto de admisión llega ANTES de que exista una herida/consulta (el paciente
-- se crea como stub). Cuando el clínico registre la herida podrá adoptarla.

alter table public.appointments
  add column if not exists intake_photo_path text;

comment on column public.appointments.intake_photo_path is
  'Ruta en el bucket privado acuity-intake ({organization_id}/{appointment_id}.ext) '
  'de la foto de la herida del formulario de admisión, ya descargada/comprimida. '
  'Sentinela "no-photo" = la cita no traía foto; "error" = no se pudo descargar '
  '(p.ej. URL de Acuity ya caducada). NULL = aún no procesada.';

-- Bucket privado. Se sube la versión YA comprimida (la Edge Function reduce el
-- peso), por eso el límite por archivo puede ser holgado.
insert into storage.buckets (id, name, public, file_size_limit)
values ('acuity-intake', 'acuity-intake', false, 15728640) -- 15 MB
on conflict (id) do nothing;

-- Lectura: misma visibilidad que la cita a la que pertenece la foto (el nombre
-- del objeto es {organization_id}/{appointment_id}.ext; el appointment_id es el
-- nombre de archivo sin extensión). Escritura: solo service role (Edge
-- Functions), por eso no hay policies de insert/update/delete.
create policy "acuity_intake_select" on storage.objects
  for select using (
    bucket_id = 'acuity-intake'
    and (
      public.is_master()
      or exists (
        select 1 from public.appointments ap
        where ap.id::text = split_part(storage.filename(name), '.', 1)
          and (
            (public.is_admin() and ap.organization_id = public.current_organization_id())
            or ap.staff_id = public.current_staff_id()
          )
      )
    )
  );
