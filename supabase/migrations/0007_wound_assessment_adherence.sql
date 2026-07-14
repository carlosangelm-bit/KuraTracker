-- =============================================================================
-- KuraTracker - Adherencia al tratamiento (captura en seguimientos)
-- =============================================================================
-- Feature "Seguimiento de principio a fin": el formulario de seguimiento
-- (visit_type='seguimiento') necesita registrar si el paciente tuvo baja
-- adherencia al tratamiento indicado desde la ultima visita, para:
--   1. Quedar documentado como parte del estado clinico de la consulta.
--   2. Alimentar (opcionalmente) el parametro bajaAdherencia de
--      KuraSheehanCheckpoint.evaluate() con un valor real en vez de un
--      default hardcodeado en false.
-- No existia ningun campo para esto en wound_assessments; se agrega aqui
-- siguiendo el mismo patron que 0005 (alter table + comment on column).
-- =============================================================================

alter table public.wound_assessments
  add column if not exists low_adherence boolean not null default false;

comment on column public.wound_assessments.low_adherence is 'TRUE si el paciente tuvo baja adherencia al tratamiento indicado desde la visita anterior (reportado por el clinico en visitas de seguimiento). Alimenta el parametro bajaAdherencia del checkpoint de Sheehan.';
