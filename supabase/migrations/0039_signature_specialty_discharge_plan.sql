-- 0039_signature_specialty_discharge_plan.sql
--
-- Feedback clínico (María), Lote 2 parte 2:
--   #6 Firma NOM-024/004: además de nombre + cédula, la firma debe incluir la
--      ESPECIALIDAD del profesional. La identidad se resuelve del staff logueado
--      (el login autentica; no se pide contraseña aparte). Se agrega:
--        - staff.especialidad          -> fuente (editable por admin)
--        - consultations.follow_up_signed_specialty -> SNAPSHOT al firmar la nota
--   #7 Plan de alta: al egresar una herida se puede explicar el motivo.
--        - wounds.discharge_note        -> texto libre del plan de alta / egreso

alter table public.staff
  add column if not exists especialidad text;
comment on column public.staff.especialidad is
  'Especialidad del profesional (para la firma NOM-024/004). Editable por admin.';

alter table public.consultations
  add column if not exists follow_up_signed_specialty text;
comment on column public.consultations.follow_up_signed_specialty is
  'Snapshot de la especialidad de quien firmó la nota de seguimiento (NOM-024/004).';

alter table public.wounds
  add column if not exists discharge_note text;
comment on column public.wounds.discharge_note is
  'Plan de alta / explicación del motivo de egreso de la herida (María 2026-07).';
