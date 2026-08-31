-- =============================================================================
-- 0103_organizations_is_test.sql — Marca de "centro de andamio/pruebas".
-- =============================================================================
-- Permite distinguir los centros de prueba de los reales (para no contaminar
-- KPIs ni listados con datos de andamio). Aditivo. profiles.is_test y
-- patients.is_test —y los filtros de KPI— van aparte, en la ronda del pendiente
-- #3 completo. NO se marcan aquí los centros existentes: esa decisión es de
-- Carlos (ver la consulta en el brief).
-- =============================================================================

alter table public.organizations
  add column if not exists is_test boolean not null default false;

comment on column public.organizations.is_test is
  'Centro de pruebas/andamio (no productivo). Se excluye de KPIs/listados reales.';
