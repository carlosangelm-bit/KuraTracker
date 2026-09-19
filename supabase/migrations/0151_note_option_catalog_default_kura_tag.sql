-- =============================================================================
-- KuraTracker - Relleno del kura_tag por defecto en el catalogo de conceptos
-- de la nota (note_option_catalog).
--
-- POR QUE: 0013 agrego la columna kura_tag pero NUNCA la relleno, y 0010 sembro
-- los conceptos sin etiqueta. Resultado: kura_tag = NULL en TODOS los centros
-- (el catalogo es global, sin organization_id), asi que la Fase 3 del protocolo
-- ("Aceptar y aplicar a la nota") no pre-marcaba nada y el aviso pedia etiquetas
-- que nadie habia puesto. Este relleno arregla los centros EXISTENTES (no solo la
-- siembra de nuevos): al ser el catalogo global, un UPDATE aqui alcanza a todos.
--
-- Mapeo = fuente unica en lib/models/note_option_catalog.dart
-- (kDefaultNoteOptionKuraTags); una prueba de Dart afirma que esta migracion y el
-- seed de la demo coinciden con esa lista (no pueden divergir).
--
-- IDEMPOTENTE y NO destructivo: solo escribe donde kura_tag IS NULL, asi que
-- NUNCA pisa una etiqueta que el centro ya haya ajustado a mano, y re-aplicarla
-- no cambia nada. Solo procedure_desc y materials_used llevan etiqueta (son los
-- campos que el motor consume; care_type/evolution no).
-- =============================================================================

update public.note_option_catalog set kura_tag = 'limpieza'
  where field = 'procedure_desc' and label = 'Limpieza con solución salina y cambio de apósito' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'desbridamiento'
  where field = 'procedure_desc' and label = 'Desbridamiento cortante parcial' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'desbridamiento'
  where field = 'procedure_desc' and label = 'Desbridamiento autolítico/enzimático' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'compresion'
  where field = 'procedure_desc' and label = 'Aplicación de terapia compresiva' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'educacion'
  where field = 'procedure_desc' and label = 'Educación al paciente/cuidador' and kura_tag is null;

update public.note_option_catalog set kura_tag = 'limpieza'
  where field = 'materials_used' and label = 'Solución salina 0.9%' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'antimicrobiano'
  where field = 'materials_used' and label = 'Yodopovidona 10%' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'aposito'
  where field = 'materials_used' and label = 'Apósito de espuma (foam)' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'aposito'
  where field = 'materials_used' and label = 'Apósito de alginato' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'aposito'
  where field = 'materials_used' and label = 'Apósito hidrocoloide' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'aposito'
  where field = 'materials_used' and label = 'Gasa estéril' and kura_tag is null;
update public.note_option_catalog set kura_tag = 'compresion'
  where field = 'materials_used' and label = 'Vendaje de compresión' and kura_tag is null;
