-- 0088_treatment_program_hourly_cadence.sql
-- Plan de consultas: además de la cadencia por DÍAS DE LA SEMANA (existente),
-- María pide poder definir la periodicidad en INTERVALOS DE HORAS (24/72/96…).
-- Se persiste la regla de cadencia para dejar el plan reconstruible/editable.
--
--   cadence_mode : 'weekly' (días de la semana, comportamiento actual) |
--                  'hourly' (cada interval_hours horas).
--   interval_hours: horas entre sesiones cuando cadence_mode='hourly'.
--   session_count : nº de sesiones a generar cuando cadence_mode='hourly'
--                   (en 'weekly' la cantidad se deriva de weeks + días).
--
-- Aditivo e idempotente. Default 'weekly' preserva los planes existentes. Sin
-- cambios de RLS (treatment_programs ya hereda sus policies).

alter table public.treatment_programs
  add column if not exists cadence_mode text not null default 'weekly',
  add column if not exists interval_hours int,
  add column if not exists session_count int;

comment on column public.treatment_programs.cadence_mode is
  'Cadencia de sesiones: weekly (días de la semana) | hourly (cada interval_hours horas).';
comment on column public.treatment_programs.interval_hours is
  'Horas entre sesiones cuando cadence_mode=hourly (p. ej. 24, 72, 96).';
comment on column public.treatment_programs.session_count is
  'Nº de sesiones a generar cuando cadence_mode=hourly.';
