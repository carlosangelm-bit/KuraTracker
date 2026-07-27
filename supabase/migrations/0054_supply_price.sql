-- =============================================================================
-- 0054_supply_price.sql — Precio de venta del insumo (distinto del costo)
-- =============================================================================
-- El insumo tiene COSTO (unit_cost: lo que paga el centro, ya existía) y PRECIO
-- de venta (unit_price: lo que se cobra al paciente y se refleja en reportes de
-- ventas). Por default el precio = costo + 30%, editable a mano por el admin.
-- El cobro (charges/charge_items) y el uso por consulta se basan en el PRECIO.
-- =============================================================================

alter table public.inventory_items
  add column if not exists unit_price numeric(10, 2);

alter table public.consultation_supply_usage
  add column if not exists unit_price numeric(10, 2);

comment on column public.inventory_items.unit_price is
  'Precio de venta al paciente (default costo +30%, editable). unit_cost = costo del centro.';
comment on column public.consultation_supply_usage.unit_price is
  'Precio de venta snapshot del insumo usado (lo que se cobra al paciente).';
