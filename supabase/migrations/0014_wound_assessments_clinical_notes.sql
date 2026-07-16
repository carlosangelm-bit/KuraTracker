-- =============================================================================
-- KuraTracker - Campo libre de notas clinicas por visita (valoracion + seguimiento)
-- =============================================================================
-- Contexto (tarea "campo libre de notas clinicas por visita"):
-- wound_assessments es la evaluacion clinica estructurada de CADA visita
-- (tanto la valoracion inicial en wound_capture_screen.dart como el
-- seguimiento en follow_up_capture_screen.dart insertan una fila aqui via
-- DataRepository.createAssessment()). clinical_notes agrega un campo de
-- texto libre y OPCIONAL para observaciones que no encajan en los campos
-- estructurados existentes (edema, dolor, exudado, infeccion, piel
-- perilesional, adherencia, etc.), aplicando por igual a ambos flujos.
--
-- Migracion ADITIVA e IDEMPOTENTE: solo agrega una columna nullable, sin
-- default distinto de NULL, sin backfill, sin tocar RLS existente (las
-- politicas ya vigentes sobre wound_assessments siguen aplicando sin
-- cambios). No crea ninguna tabla ni politica nueva.
--
-- IMPORTANTE (orden de despliegue): el codigo de esta rama
-- (feat/clinical-free-notes) lee y escribe clinical_notes en
-- wound_assessments. Sin esta columna en Supabase, el guardado de
-- cualquier valoracion o seguimiento fallaria. Por eso esta migracion
-- debe aplicarse ANTES del rebuild de produccion (igual que 0013).
-- =============================================================================

alter table public.wound_assessments
  add column if not exists clinical_notes text;

comment on column public.wound_assessments.clinical_notes is
  'Notas clínicas / observaciones libres de la visita (opcional). Complementa los campos estructurados. Aplica tanto a valoración como a seguimiento.';
