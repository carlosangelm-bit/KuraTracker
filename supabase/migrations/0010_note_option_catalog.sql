-- =============================================================================
-- KuraTracker - Catalogo de conceptos de la nota de seguimiento
-- =============================================================================
-- Contexto (refinamiento P1, punto 2 de la instruccion "Alinear KuraTracker
-- con los protocolos clinicos Kura+"): la nota de seguimiento obligatoria
-- (tipo de atencion, descripcion del procedimiento, material utilizado,
-- evolucion) requiere opciones estandarizadas por el CENTRO (no libres por
-- cada profesional), para que los reportes/auditorias sean comparables entre
-- kuradores. El catalogo lo administra el rol admin desde el panel de
-- Configuracion; el personal clinico solo selecciona (o usa "Otro" como
-- texto libre sin persistirlo al catalogo).
--
-- Diseno de la tabla:
--   field       -> identifica a que campo de la nota pertenece la opcion
--                  ('care_type' | 'procedure_desc' | 'materials_used' |
--                  'evolution'). No se usa un enum Postgres para poder
--                  agregar nuevos campos configurables a futuro sin otra
--                  migracion de tipo.
--   label       -> texto visible del concepto (chip).
--   is_active   -> desactivar en vez de borrar (no se pierde el historico
--                  de notas que ya usaron esa opcion como texto).
--   created_by  -> profile_id (admin) que lo agrego; nullable para las
--                  opciones precargadas por esta migracion (sin usuario
--                  humano asociado).
--
-- RLS (transversal, obligatorio en todo el proyecto):
--   SELECT -> todo el personal autenticado (necesitan ver los chips).
--   INSERT/UPDATE/DELETE -> solo admin, via el helper is_admin() ya
--   existente (0002_triggers_and_functions.sql). Ningun INSERT directo a
--   audit_log desde el cliente: esta tabla NO esta en la lista de tablas
--   auditadas por audit_trigger_fn (no es dato clinico de paciente, es
--   catalogo administrativo), igual que sites/treatment_components.
-- =============================================================================

create table if not exists public.note_option_catalog (
  id uuid primary key default gen_random_uuid(),
  field text not null check (field in ('care_type', 'procedure_desc', 'materials_used', 'evolution')),
  label text not null,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint note_option_catalog_field_label_unique unique (field, label)
);

comment on table public.note_option_catalog is
  'Catalogo de conceptos preconfigurados por el centro (admin) para los '
  'campos de la nota de seguimiento obligatoria. El personal clinico solo '
  'selecciona; el admin gestiona el catalogo desde Configuracion.';
comment on column public.note_option_catalog.field is
  'Campo de la nota al que pertenece esta opcion: care_type (tipo de '
  'atencion) | procedure_desc (descripcion del procedimiento) | '
  'materials_used (material utilizado) | evolution (evolucion).';
comment on column public.note_option_catalog.created_by is
  'profile_id del admin que agrego el concepto (incluye el alta '
  'espontanea de "Otro" cuando quien captura es admin). Null para las '
  'opciones precargadas por esta migracion.';

create index if not exists idx_note_option_catalog_field
  on public.note_option_catalog(field) where is_active;

alter table public.note_option_catalog enable row level security;

create policy note_option_catalog_select_all on public.note_option_catalog
  for select using (auth.uid() is not null);
create policy note_option_catalog_admin_insert on public.note_option_catalog
  for insert with check (public.is_admin());
create policy note_option_catalog_admin_update on public.note_option_catalog
  for update using (public.is_admin());
create policy note_option_catalog_admin_delete on public.note_option_catalog
  for delete using (public.is_admin());

-- Precarga de opciones base por campo (curadas segun el Instructivo de
-- Archivo / vocabulario clinico habitual de Kura+). El admin puede
-- desactivarlas o agregar mas desde Configuracion sin tocar SQL.
insert into public.note_option_catalog (field, label) values
  ('care_type', 'Curación ambulatoria'),
  ('care_type', 'Visita domiciliaria'),
  ('care_type', 'Curación en hospitalización'),
  ('care_type', 'Interconsulta'),
  ('care_type', 'Desbridamiento programado'),
  ('procedure_desc', 'Limpieza con solución salina y cambio de apósito'),
  ('procedure_desc', 'Desbridamiento cortante parcial'),
  ('procedure_desc', 'Desbridamiento autolítico/enzimático'),
  ('procedure_desc', 'Toma de medidas y fotografía de control'),
  ('procedure_desc', 'Aplicación de terapia compresiva'),
  ('procedure_desc', 'Educación al paciente/cuidador'),
  ('materials_used', 'Solución salina 0.9%'),
  ('materials_used', 'Yodopovidona 10%'),
  ('materials_used', 'Apósito de espuma (foam)'),
  ('materials_used', 'Apósito de alginato'),
  ('materials_used', 'Apósito hidrocoloide'),
  ('materials_used', 'Gasa estéril'),
  ('materials_used', 'Vendaje de compresión'),
  ('evolution', 'Favorable, con reducción de área'),
  ('evolution', 'Estable, sin cambios significativos'),
  ('evolution', 'Sin avance esperado para la semana de tratamiento'),
  ('evolution', 'Signos de infección local'),
  ('evolution', 'Mejoría del tejido de granulación')
on conflict do nothing;
