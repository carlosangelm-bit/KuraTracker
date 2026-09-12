-- =============================================================================
-- 0129_billing_catalog_unit_amounts.sql — Montos mostrables en billing_catalog.
-- =============================================================================
-- La pantalla de Licencias (rediseño) muestra total mensual, precio unitario y
-- subtotales. Hasta ahora billing_catalog solo mapeaba lookup_key → concepto y el
-- MONTO vivía únicamente en Stripe (lo resolvía license-checkout por lookup_key).
-- Para que la app (incl. la demo, sin Stripe) muestre precios SIN escribirlos a mano
-- en el Dart, el monto se guarda aquí, sembrado por migración. Stripe sigue siendo
-- quien COBRA: estos montos deben mantenerse idénticos a los prices de Stripe (IVA
-- incluido). La clave sigue siendo lookup_key; el SELECT ya está abierto (0113).
--
-- Tarifas (Carlos, cerradas 7-sep; MXN, IVA incluido). Anual = monto COMPLETO
-- (=×10 del mensual), sembrado tal cual — el Dart NUNCA multiplica.
--   clinico   400/mes  → 40000c   · anual 4000  → 400000c
--   protocolo 300/mes  → 30000c   · anual 3000  → 300000c
--   admin    1200/mes  → 120000c  · anual 12000 → 1200000c
--   insumos  1400/mes  → 140000c  · anual 14000 → 1400000c
--   comercial 900/mes  → 90000c   · anual 9000  → 900000c
-- Prueba pública: 5 asientos + 5 Kura+ + los 3 módulos (mensual) = $7,000 = techo
-- del autoservicio. (5·400 + 5·300 + 1200 + 1400 + 900.)
-- =============================================================================

alter table public.billing_catalog
  add column if not exists unit_amount integer,          -- centavos, IVA incluido
  add column if not exists currency    text not null default 'mxn';

comment on column public.billing_catalog.unit_amount is
  'Precio por unidad en CENTAVOS (IVA incluido), para MOSTRAR en la app. Debe ser '
  'idéntico al price de Stripe con el mismo lookup_key (Stripe cobra). Anual = monto '
  'completo (=×10 del mensual), no multiplicado en el cliente.';

update public.billing_catalog as b set unit_amount = v.amt
from (values
  ('clinico_mensual',    40000),
  ('clinico_anual',     400000),
  ('protocolo_mensual',  30000),
  ('protocolo_anual',   300000),
  ('admin_mensual',     120000),
  ('admin_anual',      1200000),
  ('insumos_mensual',   140000),
  ('insumos_anual',    1400000),
  ('comercial_mensual',  90000),
  ('comercial_anual',   900000)
) as v(lookup_key, amt)
where b.lookup_key = v.lookup_key;
