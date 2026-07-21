-- 0028_etiology_classifications.sql
--
-- Clasificaciones/campos faltantes por etiología (Prompt 5). Protocolos de las
-- 4 etiologías. Extiende la tabla `wounds` con columnas estructuradas (texto =
-- `name` del enum Dart correspondiente; ver lib/engine/models/kura_engine_enums.dart
-- y lib/models/wound.dart). Todas nullable y sin cambios de RLS (heredan las
-- policies existentes de `wounds`).
--
-- Se usan columnas de texto (no enums de Postgres) por consistencia con las
-- clasificaciones ya existentes (wagner_grade, ceap_class, wuwhs_grade,
-- agente_causal), evitando ALTER TYPE en migraciones futuras.

alter table public.wounds
  -- UPD (pie diabético)
  add column if not exists upd_subtipo text,             -- UpdSubtipo
  add column if not exists texas_grade text,             -- TexasGrade (0-III)
  add column if not exists texas_stage text,             -- TexasStage (A-D)
  add column if not exists idsa_iwgdf text,              -- IdsaIwgdf (grados 1-4)
  add column if not exists sensibilidad_protectora text, -- SensibilidadProtectora (monofilamento)
  -- Vascular arterial (sobre el subtipo arterial del Prompt 1)
  add column if not exists rutherford text,              -- Rutherford (0-6)
  -- LPP (reemplaza el texto libre de estadio)
  add column if not exists npuap_estadio text,           -- NpuapEstadio (I-IV, LTP, no clasificable)
  -- Quirúrgica
  add column if not exists clase_contaminacion text,     -- ClaseContaminacion
  add column if not exists tipo_cierre text,             -- TipoCierre (1ª/2ª/3ª)
  add column if not exists drenaje_tipo text,            -- DrenajeTipo
  add column if not exists sutura_tipo text,             -- SuturaTipo
  -- Egreso del episodio (estructurado)
  add column if not exists discharge_reason text;        -- MotivoEgreso

comment on column public.wounds.upd_subtipo is
  'Subtipo clínico del pie diabético: neuropatica/isquemica/neuroinfecciosa/neuroisquemica.';
comment on column public.wounds.texas_grade is
  'Universidad de Texas — grado (profundidad) 0-III.';
comment on column public.wounds.texas_stage is
  'Universidad de Texas — estadio A-D (infección/isquemia).';
comment on column public.wounds.idsa_iwgdf is
  'Gravedad de infección del pie diabético IDSA/IWGDF (grados 1-4).';
comment on column public.wounds.sensibilidad_protectora is
  'Monofilamento 10 g / sensibilidad protectora: conservada/disminuida/ausente.';
comment on column public.wounds.rutherford is
  'Categoría de Rutherford (0-6) para isquemia arterial (subtipo arterial).';
comment on column public.wounds.npuap_estadio is
  'Estadio NPUAP/EPUAP de la LPP (I-IV, lesión tisular profunda, no clasificable).';
comment on column public.wounds.clase_contaminacion is
  'Clase de contaminación CDC de la herida quirúrgica.';
comment on column public.wounds.tipo_cierre is
  'Tipo de cierre quirúrgico: primera/segunda/tercera intención.';
comment on column public.wounds.discharge_reason is
  'Motivo de egreso del episodio: cierre/alta_voluntaria/abandono/defuncion.';
