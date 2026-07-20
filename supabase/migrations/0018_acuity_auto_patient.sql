-- 0018_acuity_auto_patient.sql
--
-- Alta automática de pacientes a partir de las citas de Acuity: cuando se
-- sincroniza una cita de un Kurador activo mapeado (webhook o backfill), se
-- crea (si no existe) el paciente correspondiente, se vincula la cita a él y
-- se asigna el paciente al Kurador para que aparezca en su lista.
--
-- Este archivo solo agrega columnas/índices; la lógica vive en las Edge
-- Functions acuity-webhook / acuity-backfill (ver supabase/functions/).

-- 1) Llave de deduplicación + trazabilidad. Acuity SIEMPRE trae el email del
--    cliente; se usa como llave estable para no crear un paciente por cada cita
--    de la misma persona. NULL = paciente no originado en Acuity (alta manual).
alter table public.patients
  add column if not exists acuity_email text;

comment on column public.patients.acuity_email is
  'Email del cliente en Acuity Scheduling. Llave de deduplicación para el alta '
  'automática de pacientes desde citas (ver Edge Functions acuity-*). NULL en '
  'pacientes creados manualmente.';

-- Un solo paciente por (centro, email) para las altas automáticas. Índice
-- parcial: no restringe a los pacientes manuales (acuity_email NULL). lower()
-- para que la deduplicación sea case-insensitive.
create unique index if not exists uq_patients_org_acuity_email
  on public.patients (organization_id, lower(acuity_email))
  where acuity_email is not null;

-- 2) Vínculo cita -> paciente. Permite abrir el expediente desde la agenda y
--    evita recrear el paciente al reagendar/cambiar una misma cita.
alter table public.appointments
  add column if not exists patient_id uuid references public.patients(id);

create index if not exists idx_appointments_patient_id
  on public.appointments (patient_id);

comment on column public.appointments.patient_id is
  'Paciente de KuraTracker vinculado a esta cita (alta automática desde Acuity, '
  'ver Edge Functions). Resuelto por email dentro del centro.';
