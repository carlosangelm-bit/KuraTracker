-- =============================================================================
-- 0090_remove_test_charges.sql — Elimina los cobros de PRUEBA (0057–0060)
-- =============================================================================
-- Las migraciones 0057–0060 insertaron cobros de prueba REALES contra el
-- paciente "Paciente Prueba" ($350 / $1 / $50 / $15) que entraban al KPI
-- "Pendiente" del centro y al listado de cobros, indistinguibles en pantalla.
-- Aquí se borran, identificados por el texto de `notes`.
--
-- Cobertura de los dos escenarios SIN editar migraciones ya aplicadas (se evita
-- el riesgo de checksum):
--   - Producción: 0057–0060 ya están aplicadas y NO se re-ejecutan; este DELETE
--     las borra una vez.
--   - Base nueva: 0057–0060 corren primero y las crean; esta migración corre
--     después y las borra → resultado neto: no quedan.
--
-- FKs: charge_items.charge_id es ON DELETE CASCADE (0052) → los items se borran
-- solos; point_payments.charge_id es ON DELETE SET NULL (0055) → no hay
-- violación si algún pago de terminal quedó ligado.
--
-- Idempotente: si no hay ninguno (p. ej. ya se borraron), no hace nada.
-- NOTA: NO se toca el paciente "Paciente Prueba" (cuenta de pruebas, 0062);
-- esa decisión es de producto (ver brief de auditoría).
-- =============================================================================

do $$
declare
  v_notes text[] := array[
    'Cobro de prueba (MP)',
    'Cobro de prueba real $1 (MP)',
    'Cobro de prueba real $50 (MP)',
    'Cobro de prueba $15 (Stripe)'
  ];
  v_count integer;
begin
  delete from public.charges
    where notes = any(v_notes);
  get diagnostics v_count = row_count;
  raise notice '0090: % cobro(s) de prueba borrado(s) (charge_items en cascada).', v_count;
end $$;
