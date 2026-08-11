-- 0087_wound_assessment_lower_limb_exam.sql
-- Úlceras de miembros inferiores (etiología vascular) y pie diabético: María
-- pide registrar, como TEXTO LIBRE por visita, la exploración vascular/
-- neuropática: ITB (índice tobillo-brazo), pruebas de sensibilidad y llenado
-- capilar. Son campos descriptivos del clínico, distintos del ITB NUMÉRICO que
-- ya existe en perfusion_nutrition_data (abi_right/abi_left) y que alimenta el
-- motor Kura+. Aquí solo se documenta en texto lo observado en la visita.
--
-- Aditivo e idempotente. Sin cambios de RLS: wound_assessments ya hereda las
-- policies existentes (se escribe desde createAssessment como cualquier otro
-- campo de la valoración).

alter table public.wound_assessments
  add column if not exists itb_texto text,
  add column if not exists pruebas_sensibilidad text,
  add column if not exists llenado_capilar text;

comment on column public.wound_assessments.itb_texto is
  'Miembros inferiores/pie diabético: ITB descrito en texto libre por el clínico (distinto del ITB numérico en perfusion_nutrition_data).';
comment on column public.wound_assessments.pruebas_sensibilidad is
  'Miembros inferiores/pie diabético: pruebas de sensibilidad en texto libre.';
comment on column public.wound_assessments.llenado_capilar is
  'Miembros inferiores/pie diabético: llenado capilar en texto libre.';
