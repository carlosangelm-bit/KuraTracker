-- =============================================================================
-- 0079_patient_contact.sql — Contacto propio del paciente (email + celular)
-- =============================================================================
-- El paciente no tenía email/celular propios (solo del cuidador/responsable).
-- Se agregan para: crear el cliente en Acuity al agendar las sesiones del plan
-- y habilitar recordatorios reales, y a futuro WhatsApp/cobros.
--
-- Aditivo: solo columnas nullable; no toca RLS (las policies de patients ya
-- cubren las columnas nuevas).
-- =============================================================================

alter table public.patients
  add column if not exists email text,
  add column if not exists mobile_phone text;  -- celular del paciente

comment on column public.patients.email is
  'Email del paciente (cliente en Acuity, recordatorios).';
comment on column public.patients.mobile_phone is
  'Celular del paciente (recordatorios/WhatsApp).';
