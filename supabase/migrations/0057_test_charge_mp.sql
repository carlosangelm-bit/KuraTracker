-- =============================================================================
-- 0057_test_charge_mp.sql — Cobro de PRUEBA para validar el cobro en línea (MP)
-- =============================================================================
-- Crea un cobro PENDIENTE de $350 MXN para el paciente "Paciente Prueba", para
-- probar "Cobrar en línea (Mercado Pago)" sin capturar una consulta a mano.
--
-- Es data de prueba, NO esquema. Defensivo e idempotente:
--   - No hace nada si "Paciente Prueba" no existe.
--   - No duplica: si ya hay un cobro de prueba pendiente, no crea otro.
-- Se puede borrar después (o pagar en la prueba, con lo que pasa a 'pagado').
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
    raise notice '0057: "Paciente Prueba" no encontrado; no se crea cobro de prueba.';
    return;
  end if;

  if exists (
    select 1 from public.charges
    where patient_id = v_patient
      and status = 'pendiente'
      and notes = 'Cobro de prueba (MP)'
  ) then
    raise notice '0057: ya existe un cobro de prueba pendiente; no se duplica.';
    return;
  end if;

  v_charge := gen_random_uuid();

  insert into public.charges
    (id, organization_id, patient_id, subtotal_service, subtotal_supplies,
     total, currency, status, notes, created_at, updated_at)
  values
    (v_charge, v_org, v_patient, 350, 0, 350, 'MXN', 'pendiente',
     'Cobro de prueba (MP)', now(), now());

  insert into public.charge_items
    (id, charge_id, organization_id, kind, name, quantity, unit_price,
     line_total, created_at)
  values
    (gen_random_uuid(), v_charge, v_org, 'servicio', 'Consulta de prueba', 1,
     350, 350, now());

  raise notice '0057: cobro de prueba creado para % (org %).', v_patient, v_org;
end $$;
