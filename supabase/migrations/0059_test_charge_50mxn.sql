-- =============================================================================
-- 0059_test_charge_50mxn.sql — Cobro de prueba de $50 MXN (validación REAL MP)
-- =============================================================================
-- Cobro PENDIENTE de $50 MXN para "Paciente Prueba": monto "normal" para
-- descartar rechazos por monto demasiado bajo al validar el pago real.
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
    raise notice '0059: "Paciente Prueba" no encontrado; no se crea cobro de $50.';
    return;
  end if;

  if exists (
    select 1 from public.charges
    where patient_id = v_patient
      and status = 'pendiente'
      and notes = 'Cobro de prueba real $50 (MP)'
  ) then
    raise notice '0059: ya existe el cobro de $50 pendiente; no se duplica.';
    return;
  end if;

  v_charge := gen_random_uuid();

  insert into public.charges
    (id, organization_id, patient_id, subtotal_service, subtotal_supplies,
     total, currency, status, notes, created_at, updated_at)
  values
    (v_charge, v_org, v_patient, 50, 0, 50, 'MXN', 'pendiente',
     'Cobro de prueba real $50 (MP)', now(), now());

  insert into public.charge_items
    (id, charge_id, organization_id, kind, name, quantity, unit_price,
     line_total, created_at)
  values
    (gen_random_uuid(), v_charge, v_org, 'servicio', 'Prueba de cobro ($50)', 1,
     50, 50, now());

  raise notice '0059: cobro de $50 creado para % (org %).', v_patient, v_org;
end $$;
