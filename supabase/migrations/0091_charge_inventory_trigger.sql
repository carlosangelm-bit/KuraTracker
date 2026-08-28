-- =============================================================================
-- 0091_charge_inventory_trigger.sql — Descuento de inventario al PAGAR (trigger)
-- =============================================================================
-- Antes, el descuento de existencias vivía SOLO en `markChargePaid` (Dart, en el
-- cliente). Los webhooks de Stripe/Mercado Pago marcan el cobro pagado con un
-- UPDATE directo a `charges` y NO descontaban; una corrección por SQL tampoco.
-- Además, una vez `pagado`, la UI ya no ofrece "Registrar pago", así que el
-- código Dart nunca vuelve a correr para ese cobro → las líneas quedaban
-- `discounted = false` para siempre.
--
-- Invariante: un cobro que llega a `pagado` descuenta su inventario EXACTAMENTE
-- UNA VEZ, sin importar quién lo marcó (app, webhook Stripe/MP, sync manual o un
-- UPDATE hecho a mano en SQL). El descuento es una consecuencia del pago, así
-- que vive donde el pago se registra: un trigger AFTER UPDATE sobre `charges`.
--
-- Idempotencia:
--   - Se dispara SOLO en la transición a 'pagado' (old <> pagado). Re-marcar
--     pagado un cobro ya pagado no vuelve a descontar (= la guarda `!wasPaid`).
--   - Ruta consulta: además por el flag `consultation_supply_usage.discounted`.
--
-- Cubre las dos formas de cobro (rutas distintas en Dart):
--   - cobro de consulta  → líneas en `consultation_supply_usage` (discount=true)
--   - cobro de mostrador → líneas en `charge_items` con inventory_item_id
--
-- Demo (LocalStore): NO hay Postgres ni trigger; la ruta Dart sigue existiendo
-- y se ejecuta SOLO ahí (gateada por `_store is LocalStoreDataStore`). En
-- producción la ruta Dart se salta para no duplicar el descuento.
--
-- NOTA (espejo Shopify de Kura+): `addInventoryMovement` empujaba el ajuste a
-- Shopify best-effort desde el cliente. El trigger inserta el movimiento de
-- inventario (que es el invariante), pero NO empuja a Shopify; para centros
-- Kura+ con pago EN LÍNEA, Shopify se reconcilia en la próxima sincronización.
-- (Seguimiento aparte; ver auditoría 28-ago-2026.)
--
-- NO hace backfill de los cobros ya pagados sin descontar (puede requerir conteo
-- físico). Consulta de solo lectura para dimensionarlo (correr a mano):
--   select count(*) from public.consultation_supply_usage u
--     join public.charges c on c.consultation_id = u.consultation_id
--    where c.status = 'pagado' and u.discount is true and u.discounted is false
--      and u.inventory_item_id is not null;
-- =============================================================================

create or replace function public.discount_charge_inventory()
returns trigger
language plpgsql
security definer
set search_path = public
as $func$
begin
  -- Solo en la TRANSICIÓN a 'pagado'.
  if new.status is distinct from 'pagado'
     or old.status is not distinct from 'pagado' then
    return new;
  end if;

  if new.consultation_id is not null then
    -- Ruta CONSULTA: insumos marcados "descontar" aún no descontados.
    insert into public.inventory_movements
      (organization_id, site_id, inventory_item_id, delta, reason,
       unit_cost, patient_id, consultation_id, note, created_at)
    select
      it.organization_id, it.site_id, u.inventory_item_id, -u.quantity, 'consumo',
      coalesce(u.unit_cost, it.unit_cost), u.patient_id, new.consultation_id,
      'Consumo cobrado (consulta)', now()
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
    -- Ruta DIRECTA (mostrador): renglones con inventory_item_id. Idempotente por
    -- la guarda de transición (equivalente al `!wasPaid` del cliente).
    insert into public.inventory_movements
      (organization_id, site_id, inventory_item_id, delta, reason,
       unit_cost, patient_id, note, created_at)
    select
      it.organization_id, it.site_id, ci.inventory_item_id, -ci.quantity, 'consumo',
      it.unit_cost, new.patient_id, 'Venta cobrada (cobro directo)', now()
    from public.charge_items ci
    join public.inventory_items it on it.id = ci.inventory_item_id
    where ci.charge_id = new.id
      and ci.inventory_item_id is not null;
  end if;

  return new;
end;
$func$;

drop trigger if exists trg_discount_charge_inventory on public.charges;
create trigger trg_discount_charge_inventory
  after update of status on public.charges
  for each row
  execute function public.discount_charge_inventory();
