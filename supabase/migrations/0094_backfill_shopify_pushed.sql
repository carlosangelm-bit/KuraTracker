-- =============================================================================
-- 0094_backfill_shopify_pushed.sql — Baseline seguro del espejo Shopify (Kura+)
-- =============================================================================
-- 0092 agregó inventory_movements.shopify_pushed con DEFAULT false, así que TODO
-- movimiento histórico quedó en false. Pero esos movimientos ya se reflejaron en
-- Shopify en su momento (vía el push del cliente, _maybePushShopifyAdjust) o no
-- aplican (centros sin espejo). La nueva acción `reconcile_pending` (0094 app +
-- función) barre los `shopify_pushed = false` y los empuja; si corriera sobre el
-- histórico, RE-empujaría ajustes que Shopify ya tiene → DOBLE descuento.
--
-- Por eso se establece un baseline: todo lo existente se considera reconciliado.
-- De aquí en adelante, solo los movimientos NUEVOS que fallen su push quedan en
-- false y los recoge `reconcile_pending` en la siguiente sincronización.
-- =============================================================================

update public.inventory_movements
  set shopify_pushed = true
  where shopify_pushed = false;
