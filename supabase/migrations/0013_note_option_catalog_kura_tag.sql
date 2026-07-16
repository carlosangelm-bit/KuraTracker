-- =============================================================================
-- KuraTracker - Etiqueta de mapeo (kura_tag) en el catalogo de conceptos
-- =============================================================================
-- Contexto (tarea "protocolo Kura+ sugerido en la nota de seguimiento"):
-- note_option_catalog (0010_note_option_catalog.sql) guarda los conceptos
-- LIBRES que cada centro configura para los 4 campos de la nota de
-- seguimiento (tipo de atencion, descripcion del procedimiento, material
-- utilizado, evolucion). El motor de reglas clinicas (kura_rules_v2,
-- KuraTreatmentRulesEngine) produce, en cambio, un regimen con METODOS
-- estandarizados (p.ej. "Limpieza de la herida", "Desbridamiento",
-- "Terapia compresiva"). kura_tag es el puente entre ambos vocabularios:
-- el admin del centro etiqueta sus conceptos libres con una de las
-- categorias del motor, y la app puede entonces pre-seleccionar (nunca
-- forzar) los conceptos cuyo kura_tag coincida con el regimen sugerido
-- para la valoracion actual del seguimiento, cuando el usuario premium
-- activa el toggle "Utilizar protocolo Kura+".
--
-- Valores sugeridos (alineados con los metodos de kura_rules_v2):
--   limpieza, desbridamiento, relleno_cavidad, aposito, proteccion_piel,
--   antimicrobiano, compresion, descarga, educacion.
-- NULL = sin etiqueta (concepto libre/personalizado del centro que el
-- motor nunca auto-selecciona; comportamiento por defecto y seguro).
--
-- Migracion ADITIVA e IDEMPOTENTE: solo agrega una columna nullable, sin
-- default distinto de NULL, sin backfill, sin tocar RLS existente (las
-- 4 politicas de 0010/0011 sobre note_option_catalog siguen aplicando
-- sin cambios: SELECT para autenticados, INSERT/UPDATE/DELETE solo
-- admin via is_admin()). No crea ninguna tabla ni politica nueva.
-- =============================================================================

alter table public.note_option_catalog
  add column if not exists kura_tag text;

comment on column public.note_option_catalog.kura_tag is
  'Etiqueta opcional que mapea este concepto libre del centro a una '
  'categoria de metodo del motor Protocolo Kura+ (kura_rules_v2), para '
  'poder pre-seleccionarlo (editable, nunca forzado) cuando un usuario '
  'premium activa el toggle "Utilizar protocolo Kura+" en la nota de '
  'seguimiento. Valores sugeridos: limpieza | desbridamiento | '
  'relleno_cavidad | aposito | proteccion_piel | antimicrobiano | '
  'compresion | descarga | educacion. NULL = sin etiqueta (nunca se '
  'auto-selecciona).';
