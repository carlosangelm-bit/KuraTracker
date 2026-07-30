-- =============================================================================
-- 0066_patient_meds_allergies.sql — Medicamentos activos y alergias del paciente
-- =============================================================================
-- Campos clínicos de texto libre que faltaban en el expediente: medicamentos
-- que el paciente toma actualmente y alergias. Se capturan al abrir el
-- expediente y son editables. No cambian RLS (las policies de patients ya
-- cubren estas columnas).
-- =============================================================================

alter table public.patients
  add column if not exists active_medications text;
alter table public.patients
  add column if not exists allergies text;

comment on column public.patients.active_medications is
  'Medicamentos que el paciente toma actualmente (texto libre).';
comment on column public.patients.allergies is
  'Alergias del paciente (texto libre).';
