-- =============================================================================
-- 0109_wound_vision_corrections.sql — Correcciones del clínico sobre la
-- clasificación de tejido del motor de visión.
-- =============================================================================
-- Es DATO DE ENTRENAMIENTO para recalibrar el clasificador, NO narrativa
-- clínica: va en tabla APARTE (no en vision_meta) para no ensuciar el expediente
-- y poder exportar el conjunto con un SELECT. El export es SOLO plataforma
-- (Edge Function con service_role, capa 3) y SEUDONIMIZA wound_id en la salida
-- (sin identificadores de paciente); aquí se guarda el wound_id real para RLS.
--
-- RLS ADITIVA: mismo criterio que wound_measurements (staff activo asignado al
-- paciente de la herida, o admin). Ninguna policy existente se toca.
-- =============================================================================

create table if not exists public.wound_vision_corrections (
  id uuid primary key default gen_random_uuid(),

  -- Ancla a la medición GUARDADA. NULL a propósito cuando el clínico corrige y
  -- sale SIN aplicar la medición (el motor falló tanto que abandonó): esa fila
  -- es la señal más valiosa y entrena igual porque lleva el Lab por punto.
  -- on delete set null: si se borra la medición, la corrección se conserva.
  wound_measurement_id uuid references public.wound_measurements(id) on delete set null,

  -- Ancla siempre a la herida (para RLS y para exportar sin join). La pantalla
  -- de visión se abre para una herida concreta, así que este id existe siempre.
  wound_id uuid not null references public.wounds(id) on delete cascade,

  -- Lo que el clínico dice que es EN REALIDAD. 'brillo' permite validar el filtro
  -- especular; 'otro' (con nota) y 'no_estoy_seguro' evitan forzar etiquetas
  -- falsas que envenenarían el dataset; 'piel_no_herida' = ni siquiera es herida.
  clinician_class text not null check (clinician_class in (
    'granulacion','esfacelo','necrosis','epitelizacion',
    'piel_no_herida','brillo','otro','no_estoy_seguro'
  )),
  note text,
  -- 'otro' EXIGE nota no vacía (si no, etiqueta falsa → dataset envenenado).
  constraint corr_otro_requires_note
    check (clinician_class <> 'otro' or (note is not null and length(btrim(note)) > 0)),

  -- Reproducibilidad y calibración POR corrección.
  engine_version text not null,
  calibration_mode text check (calibration_mode in ('card','disc')),
  mm_per_px numeric,
  rectified_size jsonb, -- [w, h] de la imagen rectificada

  -- Muestras marcadas por el clínico (unos toques bastan). Cada punto:
  --   { "x": <px rectificados>, "y": <px rectificados>,
  --     "engine_class": <0..3 | 254 brillo>,   -- lo que puso el MOTOR ahí
  --     "lab": [L, a, b] }                       -- promedio de un parche ~5x5 px
  points jsonb not null,
  -- Forma mínima: array no vacío. Sin esto, un bug del cliente mete filas vacías
  -- al dataset y solo se descubre al exportar, meses después.
  constraint corr_points_shape
    check (jsonb_typeof(points) = 'array' and jsonb_array_length(points) > 0),

  -- QUIÉN corrigió y con qué ROL (concordancia entre evaluadores: distinguir
  -- una gerente clínica de un residente).
  -- created_by SIN on delete: sigue el patrón dominante del repo (deuda conocida:
  -- borrar un perfil choca hoy contra ~23 tablas; se aborda aparte, no aquí).
  created_by uuid references public.profiles(id),
  created_by_role text,

  created_at timestamptz not null default now()
);

comment on table public.wound_vision_corrections is
  'Correcciones del clínico a la clasificación de tejido del motor de visión. Dataset de entrenamiento para recalibrar el clasificador; export solo plataforma y seudonimizado. Tabla aparte para no ensuciar el expediente. DELIBERADAMENTE NO guarda referencia a la imagen: en una sesión abandonada guardaríamos una foto de paciente que el clínico decidió NO guardar; el Lab por punto basta para entrenar. NO añadir un puntero a la foto.';
comment on column public.wound_vision_corrections.wound_measurement_id is
  'Medición asociada, o NULL si el clínico corrigió y salió sin aplicar la medición (caso de fallo del motor, la señal más valiosa).';
comment on column public.wound_vision_corrections.points is
  'Puntos marcados: {x,y en px rectificados, engine_class (0..3/254), lab:[L,a,b] promedio de un parche ~5x5}.';
comment on column public.wound_vision_corrections.created_by_role is
  'Rol del autor al momento de corregir (concordancia inter-evaluador).';

create index if not exists idx_wvc_wound on public.wound_vision_corrections(wound_id);
create index if not exists idx_wvc_measurement on public.wound_vision_corrections(wound_measurement_id);
create index if not exists idx_wvc_created on public.wound_vision_corrections(created_at);

alter table public.wound_vision_corrections enable row level security;

-- SELECT: admin del centro, o staff activo asignado al paciente de la herida
-- (mismo predicado que wound_measurements). El export de plataforma NO usa estas
-- policies: corre con service_role en una Edge Function (capa 3).
create policy wvc_select on public.wound_vision_corrections
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_vision_corrections.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- INSERT/UPDATE/DELETE: mismo criterio (quien puede medir la herida puede
-- corregir su clasificación).
create policy wvc_write on public.wound_vision_corrections
  for all using (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_vision_corrections.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  )
  with check (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_vision_corrections.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );
