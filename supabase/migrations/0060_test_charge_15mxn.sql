-- =============================================================================
-- 0060_test_charge_15mxn.sql — Cobro de prueba de $15 MXN (validación Stripe)
-- =============================================================================
-- Stripe MX rechaza montos < $10. Cobro de $15 (arriba del mínimo, mínimo costo)
-- para "Paciente Prueba" y validar el link de pago de Stripe en modo real.
-- Data de prueba, defensivo e idempotente.
-- =============================================================================

do $$
declare
  v_patient uuid;
  v_org uuid;
  v_charge uuid;
begin
  select id, organization_id into v_patient, v_org
    from public.patients
    where full_name = 'Paciente Prueba'
    order by created_at
    limit 1;

  if v_patient is null then
    raise notice '0060: "Paciente Prueba" no encontrado; no se crea cobro de $15.';
    return;
  end if;

  if exists (
    select 1 from public.charges
    where patient_id = v_patient
      and status = 'pendiente'
      and notes = 'Cobro de prueba $15 (Stripe)'
  ) then
    raise notice '0060: ya existe el cobro de $15 pendiente; no se duplica.';
    return;
  end if;

  v_charge := gen_random_uuid();

  insert into public.charges
    (id, organization_id, patient_id, subtotal_service, subtotal_supplies,
     total, currency, status, notes, created_at, updated_at)
  values
    (v_charge, v_org, v_patient, 15, 0, 15, 'MXN', 'pendiente',
     'Cobro de prueba $15 (Stripe)', now(), now());

  insert into public.charge_items
    (id, charge_id, organization_id, kind, name, quantity, unit_price,
     line_total, created_at)
  values
    (gen_random_uuid(), v_charge, v_org, 'servicio', 'Prueba de cobro ($15)', 1,
     15, 15, now());

  raise notice '0060: cobro de $15 creado para % (org %).', v_patient, v_org;
end $$;
