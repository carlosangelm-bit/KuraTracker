-- =============================================================================
-- master_grants_acceptance_sandbox.sql — Aceptación de las RPC de otorgamiento a
-- mano (0132), §6 pruebas 1-4. Se corre en el editor SQL de Supabase (SANDBOX),
-- tras aplicar 0132. NO deja datos: DO block transaccional que termina lanzando una
-- excepción para forzar ROLLBACK; el resultado llega COMO EL MENSAJE de esa
-- excepción (empieza con "ROLLBACK INTENCIONAL"). Todos PASS = ok.
--
-- Simula al master con set_config('request.jwt.claims', ...) + set local role
-- authenticated (mismo patrón que license_phase1_acceptance_sandbox.sql), así
-- is_master() e auth.uid() son los REALES.
--
-- Cubre (criterio de CONDUCTA: borra la línea y la prueba cae):
--   1  master_grant_entitlement rechaza pisar una fila source='stripe'
--      (sin esto, un otorgamiento a mano rompería el barrido del webhook de 0119).
--   2  rechaza seat:clinico por debajo de consumed_seat_demand.
--   3a rechaza motivo de menos de 10 caracteres (CHECK).
--   3b rechaza vigencia ausente sin "permanente".
--   4  granted_by sale de auth.uid(), NO de un parámetro.
--
-- (El equivalente en fixture local con Postgres —donde se verificó a mano que cada
-- una se pone en ROJO al quitar su guardia— acompaña a este archivo en el commit.)
-- =============================================================================

do $$
declare
  v_master uuid;
  v_clin uuid;
  v_org uuid;
  v_demand int;
  v_gb uuid;
  r text := E'=== Aceptación otorgamientos a mano (0132) ===\n';
  ok boolean;
begin
  -- Un master real (para el jwt) y un perfil clínico-capaz distinto (para sembrar demanda).
  select id into v_master from public.profiles
   where is_active and ('master'::public.user_role = any(roles)) order by id limit 1;
  if v_master is null then
    raise exception 'Seed insuficiente: no hay un perfil master activo.';
  end if;
  select id into v_clin from public.profiles
   where is_active and public.consumes_clinical_seat(roles, role)
     and id <> v_master order by id limit 1;

  -- Centro de prueba.
  insert into public.organizations (name, center_type, is_active)
  values ('QA Otorgamientos 0132', 'clinica_heridas', true) returning id into v_org;

  -- A partir de aquí, operar COMO EL MASTER.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_master::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- ------------------------------------------------------------------ TEST 1
  insert into public.org_entitlements (organization_id, kind, key, source, status)
  values (v_org, 'module', 'insumos', 'stripe', 'active');
  ok := false;
  begin
    perform public.master_grant_entitlement(
      v_org, 'module', 'insumos', null,
      'comercial', 'razon de prueba valida', now() + interval '30 days', false);
  exception when others then
    if sqlerrm like 'GRANT_STRIPE_OWNED%' then ok := true;
    else r := r || format('FAIL 1 · mensaje inesperado: %s%s', sqlerrm, E'\n'); end if;
  end;
  r := r || case when ok
    then E'PASS 1 · rechaza pisar una fila source=stripe.\n'
    else E'FAIL 1 · un otorgamiento a mano pisó una fila source=stripe.\n' end;
  delete from public.org_entitlements where organization_id = v_org;

  -- ------------------------------------------------------------------ TEST 2
  -- Sembrar demanda ≥ 1: una membresía clínica activa en el centro de prueba.
  if v_clin is not null then
    insert into public.user_center_memberships (profile_id, organization_id, role, is_active)
    values (v_clin, v_org, 'clinico', true)
    on conflict (profile_id, organization_id) do update set is_active = true;
  end if;
  v_demand := public.consumed_seat_demand(v_org);
  if v_demand < 1 then
    r := r || E'SKIP 2 · no se pudo sembrar demanda ≥1 en este seed (verificado en fixture local).\n';
  else
    ok := false;
    begin
      perform public.master_grant_entitlement(
        v_org, 'seat', 'clinico', v_demand - 1,
        'comercial', 'razon de prueba valida', now() + interval '30 days', false);
    exception when others then
      if sqlerrm like 'GRANT_BELOW_DEMAND%' then ok := true;
      else r := r || format('FAIL 2 · mensaje inesperado: %s%s', sqlerrm, E'\n'); end if;
    end;
    r := r || case when ok
      then format('PASS 2 · rechaza seat:clinico por debajo de la demanda (%s).%s', v_demand, E'\n')
      else E'FAIL 2 · aceptó un tope por debajo de la demanda.\n' end;
  end if;
  delete from public.org_entitlements where organization_id = v_org;

  -- ----------------------------------------------------------------- TEST 3a
  ok := false;
  begin
    perform public.master_grant_entitlement(
      v_org, 'module', 'insumos', null,
      'comercial', 'ok', now() + interval '30 days', false);
  exception
    when check_violation then ok := true;
    when others then r := r || format('FAIL 3a · mensaje inesperado: %s%s', sqlerrm, E'\n');
  end;
  r := r || case when ok
    then E'PASS 3a · rechaza motivo de menos de 10 caracteres.\n'
    else E'FAIL 3a · aceptó un motivo demasiado corto.\n' end;

  -- ----------------------------------------------------------------- TEST 3b
  ok := false;
  begin
    perform public.master_grant_entitlement(
      v_org, 'module', 'insumos', null,
      'comercial', 'razon de prueba valida', null, false);
  exception when others then
    if sqlerrm like 'GRANT_NO_EXPIRY%' then ok := true;
    else r := r || format('FAIL 3b · mensaje inesperado: %s%s', sqlerrm, E'\n'); end if;
  end;
  r := r || case when ok
    then E'PASS 3b · rechaza vigencia ausente sin "permanente".\n'
    else E'FAIL 3b · aceptó sin vigencia ni permanente.\n' end;

  -- ------------------------------------------------------------------ TEST 4
  -- granted_by lo escribe la RPC desde auth.uid(); no hay parámetro para pasarlo.
  perform public.master_grant_entitlement(
    v_org, 'module', 'comercial', null,
    'comercial', 'razon de prueba valida', now() + interval '30 days', false);
  select granted_by into v_gb from public.org_entitlements
   where organization_id = v_org and kind = 'module' and key = 'comercial';
  r := r || case when v_gb = v_master
    then E'PASS 4 · granted_by = auth.uid() (lo fija la RPC, no el cliente).\n'
    else format('FAIL 4 · granted_by=%s no es auth.uid()=%s%s', v_gb, v_master, E'\n') end;

  reset role;
  raise exception E'ROLLBACK INTENCIONAL (no es un error real; no se dejaron datos).\n\n%', r;
end $$;
