-- 0086_patients_archived.sql
-- Depuración de expedientes: permite ARCHIVAR (ocultar) pacientes que ya no se
-- atienden sin borrarlos. Reversible (restaurar = archived_at -> NULL) y no
-- destructivo (los datos ligados —heridas, consultas, valoraciones— se
-- conservan). Caso de uso: el import histórico de Acuity trajo muchos pacientes
-- que no están en tratamiento; el admin/master los archiva y desaparecen de
-- listas y tableros, dejando solo el padrón vigente.
--
-- RLS: NO requiere policy nueva. patients_update (0011) ya permite a un admin de
-- la organización (o al clínico asignado) hacer UPDATE de la fila; archivar es
-- solo poner esta columna. ADITIVO: no se toca ninguna policy existente.

alter table public.patients
  add column if not exists archived_at timestamptz;

comment on column public.patients.archived_at is
  'Depuración de expedientes: fecha/hora en que se archivó (ocultó de listas y tableros). NULL = expediente vigente. Reversible; no borra datos ligados.';

-- Índice parcial: la gran mayoría queda con archived_at NULL, así que solo se
-- indexan los archivados (barato) para poder listarlos rápido al restaurar.
create index if not exists idx_patients_archived_at
  on public.patients (archived_at)
  where archived_at is not null;
