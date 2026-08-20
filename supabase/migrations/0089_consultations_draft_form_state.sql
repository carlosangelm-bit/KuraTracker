-- =============================================================================
-- 0089_consultations_draft_form_state.sql
-- Instantánea del formulario de captura de herida para BORRADORES de valoración.
-- =============================================================================
-- El borrador de una consulta de VALORACIÓN debe conservar TODO lo capturado y
-- poder reabrirse editable. En vez de escribir las tablas clínicas antes de
-- tiempo (herida/valoración/medición) y tener que deduplicar/limpiar, se guarda
-- una instantánea del estado del formulario (campos + fotos en base64) en esta
-- columna jsonb. Al reabrir el borrador se rehidrata el formulario; al finalizar
-- ("Continuar a tratamiento") se escriben las tablas y se limpia esta columna.
--
-- Aditivo: no cambia RLS (las policies vigentes de `consultations` ya cubren la
-- columna nueva). NULL = la consulta no es un borrador con instantánea.
-- =============================================================================

alter table public.consultations
  add column if not exists draft_form_state jsonb;

comment on column public.consultations.draft_form_state is
  'Instantánea del formulario de captura (valoración) para reabrir un borrador '
  'editable. Se limpia al finalizar la consulta. NULL = sin instantánea.';
