-- =============================================================================
-- 0058_test_charge_1mxn.sql — Cobro de prueba de $1 MXN (validación REAL de MP)
-- =============================================================================
-- Un cobro PENDIENTE de $1 MXN para "Paciente Prueba", para validar el cobro en
-- línea con un pago REAL mínimo (MP_MODE=prod) sin el enredo de test/real.
-- Data de prueba, defensivo e idempotente (no duplica, no falla si no existe el
-- paciente). Se puede borrar después.
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
    raise notice '0058: "Paciente Prueba" no encontrado; no se crea cobro de $1.';
    return;
  end if;

  if exists (
    select 1 from public.charges
    where patient_id = v_patient
      and status = 'pendiente'
      and notes = 'Cobro de prueba real $1 (MP)'
  ) then
    raise notice '0058: ya existe el cobro de $1 pendiente; no se duplica.';
    return;
  end if;

  v_charge := gen_random_uuid();

  insert into public.charges
    (id, organization_id, patient_id, subtotal_service, subtotal_supplies,
     total, currency, status, notes, created_at, updated_at)
  values
    (v_charge, v_org, v_patient, 1, 0, 1, 'MXN', 'pendiente',
     'Cobro de prueba real $1 (MP)', now(), now());

  insert into public.charge_items
    (id, charge_id, organization_id, kind, name, quantity, unit_price,
     line_total, created_at)
  values
    (gen_random_uuid(), v_charge, v_org, 'servicio', 'Prueba de cobro ($1)', 1,
     1, 1, now());

  raise notice '0058: cobro de $1 creado para % (org %).', v_patient, v_org;
end $$;
