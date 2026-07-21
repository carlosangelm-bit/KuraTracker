-- 0032_patient_antecedentes.sql
--
-- FASE 3 de cumplimiento (NOM-004): antecedentes de la historia clínica.
--   - Heredo-familiares (AHF): family_history (jsonb array de códigos) +
--     family_history_notes (detalle libre).
--   - Personales no patológicos (APNP): smoking, alcohol, physical_activity
--     (texto = name del enum Dart) + apnp_notes (toxicomanías, alimentación,
--     vivienda, escolaridad, etc.).
--
-- Todos nullable/opcionales. Sin cambios de RLS ni auditoría (patients ya está
-- auditada desde 0002). El tabaquismo/nutrición que cuentan para el arquetipo
-- del motor siguen viviendo en patient_comorbidities; estos APNP son la
-- descripción clínica del hábito.

alter table public.patients
  add column if not exists family_history jsonb not null default '[]'::jsonb,
  add column if not exists family_history_notes text,
  add column if not exists smoking text,            -- TabaquismoEstado
  add column if not exists alcohol text,            -- ConsumoAlcohol
  add column if not exists physical_activity text,  -- ActividadFisica
  add column if not exists apnp_notes text;

comment on column public.patients.family_history is
  'Antecedentes heredo-familiares (AHF): arreglo JSON de códigos '
  '(diabetes, hipertension, cardiopatia, cancer, ...). NOM-004.';
comment on column public.patients.apnp_notes is
  'Antecedentes personales no patológicos (APNP) libres: toxicomanías, '
  'alimentación, vivienda/servicios, escolaridad, etc. (NOM-004).';
