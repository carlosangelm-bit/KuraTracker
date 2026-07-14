-- 0009_visit_type_cierre.sql
-- Agrega el valor 'cierre' al enum Postgres `visit_type`.
-- El modelo Dart `VisitType` ya incluye `cierre` (visita de cierre con
-- 1 foto sin medicion, herida cicatrizada) desde la migracion 0008, pero
-- el tipo enum de Postgres definido en 0001_core_schema.sql solo tenia
-- ('valoracion','seguimiento','interconsulta','egreso'). Sin este ALTER,
-- cualquier insert de consultations.visit_type='cierre' en produccion
-- (Supabase real, no modo demo local) fallaria.
--
-- Nota: ALTER TYPE ... ADD VALUE no puede combinarse con su uso en la
-- misma transaccion en versiones antiguas de Postgres; por eso vive en
-- su propia migracion, separada de 0008.

alter type public.visit_type add value if not exists 'cierre';
