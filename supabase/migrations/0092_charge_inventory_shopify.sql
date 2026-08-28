-- =============================================================================
-- 0092_charge_inventory_shopify.sql — Espejo Shopify del descuento (Kura+)
-- =============================================================================
-- El trigger 0091 inserta el movimiento de inventario al pagar, pero NO empuja
-- a Shopify. Como `syncShopifyInventory` calcula delta = available(Shopify) -
-- current(local), la siguiente sincronización REVIERTE el descuento (Shopify
-- nunca se enteró). Además, antes del trigger el pago manual sí empujaba (vía
-- _maybePushShopifyAdjust); la corrección lo quitó para centros espejo.
--
-- Solución: correlacionar cada movimiento con su cobro (`charge_id`) y una
-- bandera de idempotencia (`shopify_pushed`). La función Edge `shopify-inventory`
-- gana la acción `reconcile_charge`, que empuja a Shopify los movimientos de
-- consumo de un cobro aún no empujados y los marca. La disparan app y webhooks
-- tras pagar (best-effort). Ver 0091 y la auditoría 28-ago-2026.
--
-- Idempotencia del espejo: el ajuste de Shopify es RELATIVO (delta); empujar dos
-- veces corrompería la existencia. `shopify_pushed` garantiza una sola vez.
-- =============================================================================

alter table public.inventory_movements
  add column if not exists charge_id uuid references public.charges(id) on delete set null;
alter table public.inventory_movements
  add column if not exists shopify_pushed boolean not null default false;

comment on column public.inventory_movements.charge_id is
  'Cobro que originó el movimiento (para reconciliar el espejo Shopify por cobro).';
comment on column public.inventory_movements.shopify_pushed is
  'El ajuste ya se empujó a Shopify (idempotencia del espejo Kura+).';

create index if not exists idx_inventory_movements_charge
  on public.inventory_movements(charge_id);

-- Reemplaza la función de 0091 para grabar `charge_id` en ambas rutas.
create or replace function public.discount_charge_inventory()
returns trigger
language plpgsql
security definer
set search_path = public
as $func$
begin
  if new.status is distinct from 'pagado'
     or old.status is not distinct from 'pagado' then
    return new;
  end if;

  if new.consultation_id is not null then
    insert into public.inventory_movements
      (organization_id, site_id, inventory_item_id, delta, reason,
       unit_cost, patient_id, consultation_id, charge_id, note, created_at)
    select
      it.organization_id, it.site_id, u.inventory_item_id, -u.quantity, 'consumo',
      coalesce(u.unit_cost, it.unit_cost), u.patient_id, new.consultation_id,
      new.id, 'Consumo cobrado (consulta)', now()
    from public.consultation_supply_usage u
    join public.inventory_items it on it.id = u.inventory_item_id
    where u.consultation_id = new.consultation_id
      and u.discount is true
      and u.discounted is false
      and u.inventory_item_id is not null;

    update public.consultation_supply_usage
      set discounted = true, updated_at = now()
    where consultation_id = new.consultation_id
      and discount is true
      and discounted is false
      and inventory_item_id is not null;
  else
    insert into public.inventory_movements
      (organization_id, site_id, inventory_item_id, delta, reason,
       unit_cost, patient_id, charge_id, note, created_at)
    select
      it.organization_id, it.site_id, ci.inventory_item_id, -ci.quantity, 'consumo',
      it.unit_cost, new.patient_id, new.id, 'Venta cobrada (cobro directo)', now()
    from public.charge_items ci
    join public.inventory_items it on it.id = ci.inventory_item_id
    where ci.charge_id = new.id
      and ci.inventory_item_id is not null;
  end if;

  return new;
end;
$func$;
