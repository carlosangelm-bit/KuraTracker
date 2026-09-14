-- Tests 1-4 de §6 contra el código REAL de 0132. Cada DO lanza excepción si falla;
-- con ON_ERROR_STOP=1 el exit code de psql refleja pass/fail.

-- Semilla: dos masters + un centro.
insert into public.profiles(id, roles, role) values
  ('11111111-1111-1111-1111-111111111111', array['master']::public.user_role[], 'master')
  on conflict (id) do nothing;
insert into public.profiles(id, roles, role) values
  ('22222222-2222-2222-2222-222222222222', array['master']::public.user_role[], 'master')
  on conflict (id) do nothing;
insert into public.organizations(id, name) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Org O') on conflict (id) do nothing;
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select set_config('test.demand', '0', false);

-- TEST 1: rechaza pisar una fila source='stripe'.
delete from public.org_entitlements where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
insert into public.org_entitlements(organization_id, kind, key, source, status)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'module', 'insumos', 'stripe', 'active');
do $$
declare ok boolean := false;
begin
  begin
    perform public.master_grant_entitlement(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','insumos',null,
      'comercial','razon de prueba valida', now()+interval '30 days', false);
  exception when others then
    if sqlerrm like 'GRANT_STRIPE_OWNED%' then ok := true;
    else raise exception 'TEST1 FAIL: mensaje inesperado: %', sqlerrm; end if;
  end;
  if not ok then raise exception 'TEST1 FAIL: no rebotó una fila source=stripe'; end if;
  raise notice 'TEST1 PASS';
end $$;

-- TEST 2: rechaza seat:clinico por debajo de consumed_seat_demand.
delete from public.org_entitlements where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select set_config('test.demand', '5', false);
do $$
declare ok boolean := false;
begin
  begin
    perform public.master_grant_entitlement(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','seat','clinico',3,
      'comercial','razon de prueba valida', now()+interval '30 days', false);
  exception when others then
    if sqlerrm like 'GRANT_BELOW_DEMAND%' then ok := true;
    else raise exception 'TEST2 FAIL: mensaje inesperado: %', sqlerrm; end if;
  end;
  if not ok then raise exception 'TEST2 FAIL: no rebotó por debajo de la demanda'; end if;
  raise notice 'TEST2 PASS';
end $$;
select set_config('test.demand', '0', false);

-- TEST 3a: rechaza motivo de menos de 10 caracteres (CHECK).
delete from public.org_entitlements where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$
declare ok boolean := false;
begin
  begin
    perform public.master_grant_entitlement(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','insumos',null,
      'comercial','ok', now()+interval '30 days', false);
  exception
    when check_violation then ok := true;
    when others then raise exception 'TEST3a FAIL: mensaje inesperado: %', sqlerrm;
  end;
  if not ok then raise exception 'TEST3a FAIL: motivo corto no rebotó'; end if;
  raise notice 'TEST3a PASS';
end $$;

-- TEST 3b: rechaza vigencia ausente sin "permanente".
do $$
declare ok boolean := false;
begin
  begin
    perform public.master_grant_entitlement(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','insumos',null,
      'comercial','razon de prueba valida', null, false);
  exception when others then
    if sqlerrm like 'GRANT_NO_EXPIRY%' then ok := true;
    else raise exception 'TEST3b FAIL: mensaje inesperado: %', sqlerrm; end if;
  end;
  if not ok then raise exception 'TEST3b FAIL: sin vigencia no rebotó'; end if;
  raise notice 'TEST3b PASS';
end $$;

-- TEST 4: granted_by sale de auth.uid(), no de un parámetro. Otorga como M1, luego
-- enmienda como M2: granted_by debe SEGUIR a auth.uid() (quedar en M2).
delete from public.org_entitlements where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);
select public.master_grant_entitlement(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','comercial',null,
  'comercial','razon de prueba valida uno', now()+interval '30 days', false);
select set_config('test.uid', '22222222-2222-2222-2222-222222222222', false);
select public.master_grant_entitlement(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','comercial',null,
  'cortesia','razon de prueba valida dos', now()+interval '30 days', false);
do $$
declare gb uuid;
begin
  select granted_by into gb from public.org_entitlements
   where organization_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     and kind='module' and key='comercial';
  if gb is distinct from '22222222-2222-2222-2222-222222222222' then
    raise exception 'TEST4 FAIL: granted_by=% no siguió a auth.uid()', gb;
  end if;
  raise notice 'TEST4 PASS: granted_by sigue a auth.uid()';
end $$;

select '=== ALL TESTS PASSED ===' as result;
