-- 0035_consultation_appointment_link.sql
--
-- Enlace CITA -> CONSULTA para poder navegar desde la agenda a la consulta que
-- se originó en una cita, tanto antes como después de realizarla:
--   - Antes: el bloque de la cita ofrece "Iniciar consulta", que crea la
--     consulta ya ligada a la cita.
--   - Después: el bloque ofrece "Ir a la consulta", que abre esa consulta.
--
-- La agenda tiene DOS orígenes de cita con llaves de tipo distinto:
--   - Acuity (tabla appointments, id bigint de Acuity)
--   - Manual (tabla manual_appointments, id uuid)
-- Para no acoplar la consulta a una tabla concreta ni depender de FKs (las
-- citas de Acuity se re-sincronizan y podrían reemplazarse), se guarda una
-- REFERENCIA en texto con el formato "<origen>:<id>", p.ej. "acuity:12345" o
-- "manual:8f3c...". La resolución cita<->consulta se hace en la app (la caché
-- ya tiene ambas colecciones). NULL = consulta no originada en una cita (alta
-- directa desde el expediente, comportamiento actual).

alter table public.consultations
  add column if not exists scheduled_appointment_ref text;

comment on column public.consultations.scheduled_appointment_ref is
  'Referencia a la cita que originó esta consulta, con formato "<origen>:<id>" '
  '(acuity:<bigint> | manual:<uuid>). Permite navegar cita<->consulta desde la '
  'agenda. NULL = consulta creada directamente en el expediente.';

-- Índice parcial: acelera "¿existe ya una consulta para esta cita?" sin pesar
-- sobre las consultas sin referencia (la mayoría históricas).
create index if not exists idx_consultations_scheduled_appointment_ref
  on public.consultations (scheduled_appointment_ref)
  where scheduled_appointment_ref is not null;
