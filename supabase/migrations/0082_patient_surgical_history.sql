-- =============================================================================
-- 0082_patient_surgical_history.sql — Antecedentes quirúrgicos (KT-7)
-- =============================================================================
-- Campo abierto para antecedentes quirúrgicos del paciente (feedback clínico).
-- Aditivo; no toca RLS (las policies de patients ya cubren la columna nueva).
-- =============================================================================

alter table public.patients
  add column if not exists surgical_history text;

comment on column public.patients.surgical_history is
  'Antecedentes quirúrgicos del paciente (texto abierto).';
