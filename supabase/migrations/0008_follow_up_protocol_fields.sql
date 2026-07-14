-- =============================================================================
-- KuraTracker - Alineacion Prioridad 1 (Protocolos Kura+): reevaluacion
-- integral de seguimiento, medicion 3D/manual y nota de seguimiento obligatoria
-- =============================================================================
-- Fuente: "Instruccion para el agente - Alinear KuraTracker con los
-- protocolos clinicos Kura+", Prioridad 1.
--
-- Gaps cerrados por esta migracion (los campos de evaluacion clinica -olor,
-- borde, piel perilesional, EVA de dolor- YA EXISTEN en wound_assessments
-- desde 0001; el gap ahi es solo de UI/captura en follow_up_capture_screen,
-- no de esquema):
--
--   1) Medicion 3D (heridas profundas): volumen (cm3) y una nota de medicion
--      manual para socavamiento/tunelizacion/circunferencial/geometria
--      irregular que no se resuelve con largo x ancho x profundidad.
--   2) Fotografia de seguimiento (Protocolo de Fotografias SS1.2): cada foto
--      debe quedar clasificada por "etapa" (antes de limpiar / despues de
--      limpiar sin medicion / con medicion / cierre) para poder exigir la
--      secuencia correcta segun tipo de visita (valoracion=3, seguimiento=2,
--      cierre=1) en Prioridad 2.
--   3) Nota de seguimiento obligatoria (Instructivo de Archivo): tipo de
--      atencion, descripcion del procedimiento, material utilizado,
--      evolucion, firma y cedula profesional de quien atiende. Se modela
--      como columnas de consultations (encabezado 1:1 de la visita) en vez
--      de una tabla nueva porque es exactamente 1 nota por consulta, igual
--      que vital_signs.
--   4) cedula_profesional en staff: catalogo canonico para prellenar la
--      firma/cedula de la nota de seguimiento (el clinico puede editarla si
--      quien firma es distinto de quien esta logueado).
--
-- Se sigue el mismo patron aditivo de 0005/0006/0007: alter table +
-- add column if not exists + comment on column. No se tocan RLS/audit:
-- estas columnas heredan las policies ya existentes de wound_measurements,
-- wound_photos, consultations y staff (son columnas, no tablas nuevas).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Medicion 3D / manual (wound_measurements)
-- -----------------------------------------------------------------------------
alter table public.wound_measurements
  add column if not exists volume_cm3 numeric,
  add column if not exists manual_measurement_note text;

comment on column public.wound_measurements.volume_cm3 is 'Volumen en cm3 para heridas profundas (medicion 3D). NULL si la herida es superficial y solo se mide en 2D (largo/ancho/area).';
comment on column public.wound_measurements.manual_measurement_note is 'Nota de medicion manual (hisopo/regla) para socavamiento, tunelizacion, heridas circunferenciales o de geometria irregular que no se resuelven con largo x ancho x profundidad. Protocolo de Fotografias y Medicion de Heridas.';

-- -----------------------------------------------------------------------------
-- 2. Etapa de la fotografia (wound_photos)
-- -----------------------------------------------------------------------------
alter table public.wound_photos
  add column if not exists photo_stage text;

alter table public.wound_photos drop constraint if exists wound_photos_photo_stage_check;
alter table public.wound_photos
  add constraint wound_photos_photo_stage_check
  check (photo_stage is null or photo_stage in (
    'antes_limpiar', 'despues_limpiar', 'con_medicion', 'cierre'
  ));

comment on column public.wound_photos.photo_stage is 'Etapa de la secuencia fotografica segun Protocolo de Fotografias SS1.2: antes_limpiar (solo valoracion inicial), despues_limpiar (sin medicion; valoracion y seguimiento), con_medicion (valoracion y seguimiento), cierre (unica foto de reporte final, herida cicatrizada, sin medicion). NULL permitido para fotos historicas/importadas sin clasificar.';

-- -----------------------------------------------------------------------------
-- 3. Nota de seguimiento obligatoria (consultations)
-- -----------------------------------------------------------------------------
alter table public.consultations
  add column if not exists follow_up_care_type text,
  add column if not exists follow_up_procedure_desc text,
  add column if not exists follow_up_materials_used text,
  add column if not exists follow_up_evolution text,
  add column if not exists follow_up_signed_by text,
  add column if not exists follow_up_signed_license text;

comment on column public.consultations.follow_up_care_type is 'Nota de seguimiento (Instructivo de Archivo): tipo de atencion brindada. Obligatorio para visit_type=seguimiento (validado en la app, sin campos vacios).';
comment on column public.consultations.follow_up_procedure_desc is 'Nota de seguimiento: descripcion del procedimiento realizado durante la visita.';
comment on column public.consultations.follow_up_materials_used is 'Nota de seguimiento: material utilizado durante la atencion.';
comment on column public.consultations.follow_up_evolution is 'Nota de seguimiento: evolucion de la herida/paciente reportada por el clinico.';
comment on column public.consultations.follow_up_signed_by is 'Nota de seguimiento: nombre de quien firma/atiende la visita (snapshot al momento de documentar, puede prellenarse desde staff.full_name pero es editable).';
comment on column public.consultations.follow_up_signed_license is 'Nota de seguimiento: numero de cedula profesional de quien firma (snapshot, prellenable desde staff.cedula_profesional).';

-- -----------------------------------------------------------------------------
-- 4. Catalogo canonico de cedula profesional (staff)
-- -----------------------------------------------------------------------------
alter table public.staff
  add column if not exists cedula_profesional text;

comment on column public.staff.cedula_profesional is 'Numero de cedula profesional del personal sanitario. Se usa para prellenar la firma de la nota de seguimiento obligatoria.';
