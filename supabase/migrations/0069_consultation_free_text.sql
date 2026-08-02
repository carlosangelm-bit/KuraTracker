-- =============================================================================
-- 0069_consultation_free_text.sql — Campos libres de la consulta
-- =============================================================================
-- Tres campos de texto libre en la consulta:
--   - specialist_notes: notas que escribe el especialista.
--   - visit_summary: resumen de la consulta (se autollenará con Plaud AI).
--   - transcript: transcripción completa (privacidad: solo la ve el admin del
--     centro; el gating es en la app).
-- =============================================================================

alter table public.consultations
  add column if not exists specialist_notes text;
alter table public.consultations
  add column if not exists visit_summary text;
alter table public.consultations
  add column if not exists transcript text;

comment on column public.consultations.transcript is
  'Transcripción completa de la consulta (Plaud AI). Solo visible para el admin del centro (gating en la app).';
