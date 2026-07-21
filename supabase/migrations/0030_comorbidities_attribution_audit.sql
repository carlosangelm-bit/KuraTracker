-- 0030_comorbidities_attribution_audit.sql
--
-- FASE 1 de cumplimiento (NOM-004/024): las comorbilidades son los
-- Antecedentes Personales Patológicos (APP) del expediente. Se capturan en la
-- apertura del paciente y pueden agregarse/actualizarse con el tiempo. La norma
-- exige que cada registro quede FECHADO, ATRIBUIDO al profesional y AUDITADO
-- (bitácora inalterable), sin borrado retroactivo.
--
-- La tabla patient_comorbidities ya tiene `noted_at` (fecha). Aquí se agrega:
--   1) noted_by  -> atribución al profesional que registró/actualizó el APP.
--   2) trigger de auditoría (audit_trigger_fn) -> traza inmutable de cada
--      alta/cambio, igual que el resto de tablas clínicas (0002).
--
-- Modelo append-only: una fila por (patient_id, code) con su `status`
-- (presente/negado/no_evaluado); el HISTORIAL de cambios de estado vive en
-- audit_log (old/new + actor + fecha). No se borra: dejar de aplicar = marcar
-- `negado`. Ver DataRepository.setComorbidity.

alter table public.patient_comorbidities
  add column if not exists noted_by uuid references public.staff(id);

comment on column public.patient_comorbidities.noted_by is
  'Profesional (staff) que registró o actualizó por última vez este APP. '
  'Junto con noted_at da la atribución fecha+autor que exige la NOM-004.';

-- Auditoría (dato clínico del expediente): faltaba el trigger en esta tabla.
drop trigger if exists trg_audit_patient_comorbidities on public.patient_comorbidities;
create trigger trg_audit_patient_comorbidities
  after insert or update or delete on public.patient_comorbidities
  for each row execute function public.audit_trigger_fn();
