-- =============================================================================
-- 0074_mp_point_terminal.sql — Cobro con terminal Mercado Pago Point (push)
-- =============================================================================
-- 0055 dejó la BANDEJA de conciliación y el webhook/pull que ligan un pago a su
-- cobro por external_reference. Faltaba el PUSH: enviar la orden (payment intent)
-- a la terminal física para que pida la tarjeta. Esto agrega:
--   1) organizations.mp_point_device_id — la terminal Point asignada al centro
--      (el master/admin la elige; el device_id lo lista la Edge Function).
--   2) point_payments.mp_intent_id — id del payment intent enviado a la terminal
--      (permite consultar/cancelar la orden antes de que se pague).
--   3) RPC set_mp_point_device — master o admin del centro fija la terminal.
--
-- Aditivo; NO toca RLS existente (las policies de 0055 ya cubren la columna
-- nueva de point_payments; organizations ya es legible por su centro).
-- =============================================================================

alter table public.organizations
  add column if not exists mp_point_device_id text;

comment on column public.organizations.mp_point_device_id is
  'Terminal Mercado Pago Point asignada al centro (device_id de la Point Integration API). NULL = sin terminal configurada.';

alter table public.point_payments
  add column if not exists mp_intent_id text;   -- payment intent enviado a la terminal

create index if not exists idx_point_payments_intent
  on public.point_payments(mp_intent_id);

-- RPC: fija la terminal Point del centro (master o admin del propio centro),
-- mismo patrón de gate que set_shift_config (0046).
create or replace function public.set_mp_point_device(p_org uuid, p_device_id text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.is_master()
          or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado para configurar la terminal de este centro';
  end if;
  update public.organizations
    set mp_point_device_id = nullif(trim(coalesce(p_device_id, '')), '')
    where id = p_org;
end;
$$;

grant execute on function public.set_mp_point_device(uuid, text) to authenticated;
