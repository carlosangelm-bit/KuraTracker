-- =============================================================================
-- KuraTracker - Esquema core (Postgres / Supabase)
-- =============================================================================
-- Diseño limpio y estandar pensado para:
--   1) Operar la clinica Kura+ / CuraMas durante el piloto.
--   2) Coexistir con eKare (importacion/exportacion CSV, folios espejo).
--   3) Facilitar una migracion total futura desde eKare (tablas normalizadas,
--      catalogos explicitos, sin logica oculta en la capa de aplicacion).
--
-- Convenciones:
--   - PK: uuid (gen_random_uuid()) para todas las tablas transaccionales.
--   - Folios legibles (EXP2025-0001, K2024-0001, PA2026-0001) como columnas
--     "folio" UNIQUE, generadas por trigger secuencial por año.
--   - Soft-delete via columna "activo boolean" en catalogos maestros
--     (pacientes, personal, sitios) para no perder trazabilidad.
--   - Auditoria: tabla generica audit_log + trigger AFTER en tablas clinicas.
--   - RLS habilitado en TODAS las tablas con datos clinicos.
-- =============================================================================

create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- 1. ROLES Y USUARIOS
-- -----------------------------------------------------------------------------

create type user_role as enum ('admin', 'clinico');

-- Perfil de usuario de la app, vinculado 1:1 a auth.users (Supabase Auth).
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role user_role not null default 'clinico',
  full_name text not null,
  email text not null,
  phone text,
  is_active boolean not null default true,
  premium_enabled boolean not null default false, -- activa "Protocolo Kura+" (a nivel cuenta/clinica)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Perfil de usuario de la app (extiende auth.users). El rol admin gestiona personal, sitios, pacientes y la funcion premium.';
comment on column public.profiles.premium_enabled is 'Si TRUE, el usuario puede activar "Utilizar protocolo Kura+" en sus consultas.';

-- -----------------------------------------------------------------------------
-- 2. SITIOS (multi-sede: clinicas Kura+, domicilio, etc.)
-- -----------------------------------------------------------------------------

create table public.sites (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind text not null default 'clinica', -- 'clinica' | 'domicilio' | 'hospital' | 'otro'
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.sites is 'Sitios/sedes donde se atiende: clinicas Kura+, domicilios, hospitales, etc.';

-- -----------------------------------------------------------------------------
-- 3. PERSONAL SANITARIO (folio tipo K2024-0001)
-- -----------------------------------------------------------------------------

create sequence public.staff_folio_seq;

create table public.staff (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  folio text unique not null,
  full_name text not null,
  role_title text not null default 'Kurador', -- Kurador, Medico, Enfermera, etc.
  primary_site_id uuid references public.sites(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.staff is 'Registro de personal sanitario (kuradores, medicos). Folio tipo K2024-0001.';

-- Asignacion de pacientes a personal sanitario (N:M) — "ve solo sus pacientes asignados".
-- NOTA: la FK hacia public.patients(id) se agrega mas abajo via ALTER TABLE
-- (seccion 4), una vez que la tabla patients ya existe, para evitar el error
-- "relation public.patients does not exist" al ejecutar este script de arriba
-- a abajo en el SQL Editor.
create table public.staff_patient_assignments (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  patient_id uuid not null,
  assigned_at timestamptz not null default now(),
  unique (staff_id, patient_id)
);

-- -----------------------------------------------------------------------------
-- 4. PACIENTES / EXPEDIENTES (folio tipo EXP2025-XXXX / PA2026-XXXX)
-- -----------------------------------------------------------------------------

create table public.patients (
  id uuid primary key default gen_random_uuid(),
  folio text unique not null, -- EXP2025-0001 o PA2026-0001
  full_name text not null,
  birth_date date,
  sex text, -- 'M' | 'F' | 'otro'
  primary_site_id uuid references public.sites(id),
  mobility text, -- 'ambulatorio' | 'silla_ruedas' | 'encamado' | 'otro'
  has_identified_caregiver boolean not null default false,
  caregiver_name text,
  caregiver_phone text,
  fragile_patient boolean not null default false,
  background_notes text, -- antecedentes libres
  ekare_external_id text, -- para interoperabilidad / mapeo con eKare
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.patients is 'Pacientes/expedientes. Folio configurable EXP2025-XXXX / PA2026-XXXX. ekare_external_id permite mapear el registro importado desde eKare.';

alter table public.staff_patient_assignments
  add constraint fk_assignments_patient
  foreign key (patient_id) references public.patients(id) on delete cascade;

-- Comorbilidades del paciente (catalogo cerrado + estado), usado por el motor (n_comorb_struct).
create type comorbidity_code as enum (
  'diabetes_mellitus',
  'enfermedad_arterial_periferica',
  'insuficiencia_venosa_cronica',
  'insuficiencia_renal_cronica',
  'enfermedad_cardiovascular',
  'inmunosupresion',
  'obesidad',
  'tabaquismo_activo',
  'malnutricion',
  'movilidad_reducida'
);

create type comorbidity_status as enum ('presente', 'negado', 'no_evaluado');

create table public.patient_comorbidities (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  code comorbidity_code not null,
  status comorbidity_status not null default 'no_evaluado',
  noted_at timestamptz not null default now(),
  unique (patient_id, code)
);

comment on table public.patient_comorbidities is 'Solo status=presente cuenta para n_comorb_struct en el motor Kura+ (8.1). no_evaluado y negado NO cuentan.';

-- -----------------------------------------------------------------------------
-- 5. CONSULTAS
-- -----------------------------------------------------------------------------

create type visit_type as enum ('valoracion', 'seguimiento', 'interconsulta', 'egreso');

create table public.consultations (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  staff_id uuid not null references public.staff(id),
  site_id uuid not null references public.sites(id),
  visit_type visit_type not null default 'valoracion',
  visit_date date not null default current_date,
  vital_signs jsonb, -- {"ta":"120/80","fc":78,"temp":36.5,...}
  is_draft boolean not null default false, -- captura incompleta guardada como borrador
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.consultations is 'Encabezado de consulta: fecha, sitio, expediente, personal, tipo de visita.';

-- -----------------------------------------------------------------------------
-- 6. HERIDAS
-- -----------------------------------------------------------------------------

create type wound_etiology as enum (
  'lpp', 'vascular', 'quirurgica', 'traumatica', 'pie_diabetico', 'otra'
);

create table public.wounds (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  etiology wound_etiology not null,
  subtype text, -- catalogo dependiente de etiologia (texto libre validado en app)
  body_location_primary text not null, -- codigo de region anatomica (mapa corporal)
  body_location_secondary text,
  onset_date date,
  -- Campos condicionales por etiologia (8.1 UX: divulgacion progresiva)
  wagner_grade text, -- 'g0'..'g5' (pie diabetico)
  ceap_class text, -- 'c0'..'c6' (vascular)
  wuwhs_grade text, -- 'g1'..'g4' (quirurgica)
  agente_causal text, -- 'mordedura'|'arma_fuego'|'aplastamiento'|'punzocortante'|'otro' (traumatica)
  is_active boolean not null default true, -- false = herida cerrada/cicatrizada
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.wounds is 'Herida individual del paciente. Puede tener multiples consultas/mediciones a lo largo del tiempo.';

-- -----------------------------------------------------------------------------
-- 7. EVALUACIONES CLINICAS (por consulta + herida)
-- -----------------------------------------------------------------------------

create table public.wound_assessments (
  id uuid primary key default gen_random_uuid(),
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  wound_id uuid not null references public.wounds(id) on delete cascade,
  glucose_mg_dl numeric,
  first_assessment_date date,
  edema text, -- catalogo: 'ninguno'|'leve'|'moderado'|'severo'
  pain boolean,
  pain_type text,
  pain_duration text,
  pain_vas smallint check (pain_vas between 0 and 10),
  exudate_type text, -- seroso|sanguinolento|serosanguinolento|purulento|otro
  exudate_amount text, -- ninguno|escaso|moderado|abundante
  infection_criteria text[] default '{}', -- criterios IWII multi-seleccion
  odor text, -- ninguno|leve|moderado|fuerte
  wound_edge text, -- catalogo
  perilesional_skin text[] default '{}', -- multi-seleccion
  created_at timestamptz not null default now()
);

comment on table public.wound_assessments is 'Evaluacion clinica (paso 2): signos, dolor, exudado, infeccion (IWII), borde, piel perilesional.';

-- -----------------------------------------------------------------------------
-- 8. MEDICIONES SERIADAS (dimensiones + composicion del lecho)
-- -----------------------------------------------------------------------------

create table public.wound_measurements (
  id uuid primary key default gen_random_uuid(),
  wound_id uuid not null references public.wounds(id) on delete cascade,
  consultation_id uuid references public.consultations(id) on delete cascade,
  measured_at date not null default current_date,
  length_cm numeric not null,
  width_cm numeric not null,
  area_cm2 numeric not null, -- autocalculada largo*ancho en la app; se persiste para historicos/eKare
  depth_cm numeric not null default 0,
  tunneling boolean not null default false,
  undermining boolean not null default false,
  granulation_pct numeric not null default 0 check (granulation_pct between 0 and 100),
  slough_pct numeric not null default 0 check (slough_pct between 0 and 100),
  necrosis_pct numeric not null default 0 check (necrosis_pct between 0 and 100),
  epithelialization_pct numeric not null default 0 check (epithelialization_pct between 0 and 100),
  captured_before_debridement boolean not null default true, -- regla de captura clinica (6.1)
  created_at timestamptz not null default now(),
  constraint bed_composition_sum_check check (
    granulation_pct + slough_pct + necrosis_pct + epithelialization_pct <= 100.01
  )
);

comment on table public.wound_measurements is 'Medicion seriada: permite calcular reduccion de area en el tiempo y alimenta el motor Kura+ (necrosis_f, esfacelo_f, depth_f, logarea).';
comment on column public.wound_measurements.captured_before_debridement is 'TRUE si la composicion del lecho se registro ANTES de curar/desbridar (regla de captura clinica obligatoria).';

-- Perfusion y nutricion (por consulta, no por medicion — cambian con menor frecuencia)
create table public.perfusion_nutrition_data (
  id uuid primary key default gen_random_uuid(),
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  wound_id uuid not null references public.wounds(id) on delete cascade,
  abi_right numeric, -- indice tobillo-brazo pie derecho
  abi_left numeric,
  is_lower_extremity boolean not null default false,
  albumin_g_dl numeric,
  created_at timestamptz not null default now()
);

comment on table public.perfusion_nutrition_data is 'ABI/ITB (ambos pies) y albumina serica — usados por los ajustes clinicos del motor (8.2). ABI solo aplica a extremidad inferior.';

-- -----------------------------------------------------------------------------
-- 9. EVIDENCIA FOTOGRAFICA
-- -----------------------------------------------------------------------------

create table public.wound_photos (
  id uuid primary key default gen_random_uuid(),
  wound_id uuid not null references public.wounds(id) on delete cascade,
  consultation_id uuid references public.consultations(id) on delete cascade,
  measurement_id uuid references public.wound_measurements(id) on delete set null,
  storage_path text not null, -- ruta en Supabase Storage bucket 'wound-evidence'
  taken_at timestamptz not null default now(),
  is_baseline boolean not null default false, -- fotografia basal para comparativas
  annotations jsonb, -- anotaciones sobre la imagen (marcas, escala de referencia)
  size_bytes bigint,
  created_at timestamptz not null default now()
);

comment on table public.wound_photos is 'Evidencia fotografica. Limite de tamano por lote (17MB) validado en la app antes de subir.';

-- -----------------------------------------------------------------------------
-- 10. TRATAMIENTO / ABORDAJE
-- -----------------------------------------------------------------------------

create table public.treatment_plans (
  id uuid primary key default gen_random_uuid(),
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  wound_id uuid not null references public.wounds(id) on delete cascade,
  used_kura_protocol boolean not null default false, -- "Utilizar protocolo Kura+" activado
  final_description text, -- editor de texto enriquecido (HTML/markdown) / dictado por voz
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.treatment_components (
  id uuid primary key default gen_random_uuid(),
  treatment_plan_id uuid not null references public.treatment_plans(id) on delete cascade,
  method text not null, -- Desbridamiento, Limpieza, Antisepticos, Proteccion, Aposito, Infeccion...
  product text not null, -- subseleccion de producto
  origin text not null default 'manual', -- 'manual' | 'kura_suggested' | 'kura_edited'
  sort_order int not null default 0
);

comment on table public.treatment_components is 'origin indica si el componente fue elegido manualmente o sugerido/editado por el motor Kura+ (trazabilidad, seccion 9).';

-- -----------------------------------------------------------------------------
-- 11. RECOMENDACION KURA+ (salida del motor, seccion 8 completa)
-- -----------------------------------------------------------------------------

create type clinician_decision as enum ('pendiente', 'aceptada', 'editada', 'rechazada');

create table public.kura_recommendations (
  id uuid primary key default gen_random_uuid(),
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  wound_id uuid not null references public.wounds(id) on delete cascade,
  treatment_plan_id uuid references public.treatment_plans(id) on delete set null,

  model_version text not null, -- p.ej. 'kura_model_v2'
  adjustments_version text not null, -- p.ej. 'kura_adjustments_v1'
  rules_version text not null, -- p.ej. 'kura_rules_v1'

  prob_a numeric not null check (prob_a between 0 and 1),
  prob_b numeric not null check (prob_b between 0 and 1),
  prob_c numeric not null check (prob_c between 0 and 1),
  dominant_scenario text not null check (dominant_scenario in ('A', 'B', 'C')),
  commercial_phenotype text, -- A1/A2/A3/A4

  regimen jsonb not null default '[]', -- lista de {metodo, producto, justificacion, es_alerta}
  interconsultas jsonb not null default '[]', -- lista de {especialidad, motivo, es_urgente}
  alertas jsonb not null default '[]', -- lista de strings

  debug_features jsonb, -- features estandarizados (auditoria/validacion prospectiva)
  debug_raw_scores jsonb,

  clinician_decision clinician_decision not null default 'pendiente',
  clinician_decision_at timestamptz,
  clinician_notes text,

  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table public.kura_recommendations is 'Salida versionada del motor "Protocolo Kura+" (8.1-8.4). Es el registro central de trazabilidad para validacion prospectiva (seccion 9 y 11).';

-- -----------------------------------------------------------------------------
-- 12. CHECKPOINT DE SEGUIMIENTO (regla de Sheehan, seccion 8.5)
-- -----------------------------------------------------------------------------

create table public.sheehan_checkpoints (
  id uuid primary key default gen_random_uuid(),
  wound_id uuid not null references public.wounds(id) on delete cascade,
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  week_number int not null,
  baseline_area_cm2 numeric not null,
  current_area_cm2 numeric not null,
  raw_reduction_pct numeric not null,
  adjusted_reduction_pct numeric not null,
  closure_threshold_pct numeric not null,
  alert_threshold_pct numeric not null,
  decision text not null check (decision in ('confirmar_cierre', 'extender_observacion', 'reclasificar_c')),
  penalties_applied text[] default '{}',
  created_at timestamptz not null default now()
);

comment on table public.sheehan_checkpoints is 'Checkpoint de seguimiento (8.5): compara area actual vs basal en semanas clave y decide cierre/observacion/reclasificacion.';

-- -----------------------------------------------------------------------------
-- 13. BITACORA DE AUDITORIA
-- -----------------------------------------------------------------------------

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id),
  actor_role text,
  action text not null, -- 'insert' | 'update' | 'delete'
  table_name text not null,
  record_id uuid,
  old_data jsonb,
  new_data jsonb,
  occurred_at timestamptz not null default now()
);

comment on table public.audit_log is 'Bitacora de auditoria de cambios sobre tablas clinicas sensibles (seccion 2, requisito de seguridad).';

create index idx_audit_log_table_record on public.audit_log(table_name, record_id);
create index idx_audit_log_actor on public.audit_log(actor_id);

-- -----------------------------------------------------------------------------
-- 14. IMPORTACION / EXPORTACION (interoperabilidad eKare)
-- -----------------------------------------------------------------------------

create table public.import_batches (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'ekare_csv', -- 'ekare_csv' | 'manual_csv'
  imported_by uuid references auth.users(id),
  field_mapping jsonb not null default '{}', -- mapeo configurable de columnas CSV -> campos internos
  total_rows int not null default 0,
  success_rows int not null default 0,
  error_rows int not null default 0,
  error_details jsonb default '[]',
  status text not null default 'pending', -- pending|processing|completed|failed
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

comment on table public.import_batches is 'Registro de lotes de importacion CSV desde eKare (o manual), con mapeo de campos configurable para facilitar la migracion total futura.';

-- Indices utiles para consultas por paciente/herida/fecha (requisito explicito)
create index idx_consultations_patient_date on public.consultations(patient_id, visit_date desc);
create index idx_wounds_patient on public.wounds(patient_id);
create index idx_measurements_wound_date on public.wound_measurements(wound_id, measured_at desc);
create index idx_photos_wound on public.wound_photos(wound_id);
create index idx_recommendations_wound on public.kura_recommendations(wound_id);
create index idx_patients_folio on public.patients(folio);
create index idx_staff_folio on public.staff(folio);
