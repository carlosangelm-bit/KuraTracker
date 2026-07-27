-- =============================================================================
-- 0056_payments_provider.sql — Ledger de conciliación multi-proveedor
-- =============================================================================
-- Generaliza la bandeja de conciliación (point_payments, 0055) para que sirva a
-- CUALQUIER pasarela, no solo Mercado Pago Point: se agrega `provider`. Así el
-- mismo ledger recibe Mercado Pago (Point/online), Acuity (prepago), Clip,
-- Stripe, PayPal o manual, todos ligados al mismo cobro/paciente.
-- Aditivo e idempotente.
-- =============================================================================

alter table public.point_payments
  add column if not exists provider text not null default 'mercadopago_point';
  -- mercadopago_point | mercadopago | acuity | clip | stripe | paypal | manual

-- Filas previas (0055) eran todas de terminal Point.
update public.point_payments
  set provider = 'mercadopago_point'
  where provider is null or provider = '';

create index if not exists idx_point_payments_provider
  on public.point_payments(provider);

comment on column public.point_payments.provider is
  'Pasarela de origen del pago (mercadopago_point | mercadopago | acuity | clip | stripe | paypal | manual).';
