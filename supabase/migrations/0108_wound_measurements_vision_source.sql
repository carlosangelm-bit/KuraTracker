-- =============================================================================
-- 0108_wound_measurements_vision_source.sql — Origen de la medición (motor de visión)
-- =============================================================================
-- El motor de visión on-device (lib/engine/vision) puede proponer largo, ancho
-- y composición del lecho a partir de una foto con referencia de escala
-- (tarjeta WoundCalibrate con AprilTags, o disco de referencia). El clínico
-- revisa y puede editar los valores antes de guardar. Para la trazabilidad
-- clínica hace falta saber DE DÓNDE salió cada medición y con qué calidad.
--
-- Decisión de diseño: `area_cm2` NO cambia de significado. Sigue siendo el
-- estimado por elipse (L × A × 0,785) que alimenta el modelo pronóstico
-- (logarea), calibrado con ese estimado. El área REAL por planimetría del
-- motor va en una columna aparte (`area_planimetric_cm2`) hasta que el equipo
-- clínico valide su uso en el pronóstico (misma cautela que el cambio
-- rectángulo → elipse, ver docs/engine/medicion_oficial.md).
--
-- Las columnas heredan las policies existentes de wound_measurements (RLS
-- aditiva; no se toca ninguna policy).
-- =============================================================================

alter table public.wound_measurements
  add column if not exists measurement_source text not null default 'manual';

alter table public.wound_measurements
  drop constraint if exists wound_measurements_measurement_source_chk;

alter table public.wound_measurements
  add constraint wound_measurements_measurement_source_chk
  check (measurement_source in ('manual', 'vision_card', 'vision_disc', 'vision_manual_trace'));

alter table public.wound_measurements
  add column if not exists area_planimetric_cm2 numeric
  check (area_planimetric_cm2 is null or area_planimetric_cm2 >= 0);

alter table public.wound_measurements
  add column if not exists vision_meta jsonb;

comment on column public.wound_measurements.measurement_source is
  'Origen de largo/ancho/composición: manual (regla e hisopo) | vision_card (motor de visión, tarjeta WoundCalibrate, perspectiva corregida) | vision_disc (disco de referencia, solo escala) | vision_manual_trace (contorno trazado por el clínico sobre la foto calibrada). El clínico siempre puede editar los valores propuestos (vision_meta.edited).';

comment on column public.wound_measurements.area_planimetric_cm2 is
  'Área por planimetría (conteo de píxeles calibrados) del motor de visión. Se guarda aparte de area_cm2 (estimado por elipse que alimenta el pronóstico) hasta validar clínicamente su uso.';

comment on column public.wound_measurements.vision_meta is
  'Trazabilidad del motor de visión: engine_version, mode, mm_per_px, compuertas de calidad (gates), contorno en px de la imagen rectificada, medidas crudas y composición estimada. NULL en mediciones manuales.';
