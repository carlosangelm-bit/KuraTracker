-- Pruebas de las correcciones de 0133 contra el código REAL (fixture + 0132 + 0133).
-- Requieren un evento de Stripe (por eso el job migrations no las podía detectar).
-- Cada DO lanza excepción si falla; con ON_ERROR_STOP=1 el exit code lo refleja.

insert into public.profiles(id, roles, role) values
  ('11111111-1111-1111-1111-111111111111', array['master']::public.user_role[], 'master')
  on conflict (id) do nothing;
insert into public.organizations(id, name) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Org O') on conflict (id) do nothing;
select set_config('test.uid', '11111111-1111-1111-1111-111111111111', false);

-- ============================================================ TEST RT (ida y vuelta)
-- Otorgar module:insumos a mano; luego Stripe vende esa MISMA clave → no debe reventar,
-- la fila queda source='stripe' con los cuatro campos manuales en null, y hay bitácora
-- action='stripe_takeover'.
delete from public.org_entitlements where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
delete from public.org_entitlement_log where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
update public.organizations set stripe_subscription_id = null where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

select public.master_grant_entitlement(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','insumos',null,
  'comercial','razon de prueba valida', now()+interval '30 days', false);

-- Stripe toma la clave (si faltan las 4 líneas de 0133, esto revienta con el CHECK).
select public.apply_stripe_subscription_event(
  'evt_rt_1','customer.subscription.updated','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'sub_rt','active', now()+interval '30 days',
  jsonb_build_array(jsonb_build_object(
    'lookup_key','insumos_lk','quantity',0,'subscription_item_id','si_rt','unit_amount',null)));

do $$
declare r public.org_entitlements%rowtype; n int;
begin
  select * into r from public.org_entitlements
   where organization_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and kind='module' and key='insumos';
  if r.source <> 'stripe' then raise exception 'TESTRT FAIL: source=% (esperado stripe)', r.source; end if;
  if r.grant_type is not null or r.reason is not null or r.granted_by is not null or r.is_permanent then
    raise exception 'TESTRT FAIL: campos manuales no quedaron en null (grant_type=%, reason=%, granted_by=%, is_permanent=%)',
      r.grant_type, r.reason, r.granted_by, r.is_permanent;
  end if;
  select count(*) into n from public.org_entitlement_log
   where organization_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and kind='module' and key='insumos'
     and action='stripe_takeover';
  if n < 1 then raise exception 'TESTRT FAIL: no se registró stripe_takeover en la bitácora'; end if;
  raise notice 'TESTRT PASS: Stripe tomó la clave sin reventar, campos manuales en null, bitácora ok';
end $$;

-- ============================================================ TEST B1 (cancelada → pasa)
-- Una fila de Stripe CANCELADA sí se puede tomar a mano; al tomarla, se sueltan los ids.
delete from public.org_entitlements where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
insert into public.org_entitlements(organization_id, kind, key, source, status,
  stripe_subscription_id, stripe_subscription_item_id)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','insumos','stripe','canceled','sub_c','si_c');
do $$
declare r public.org_entitlements%rowtype;
begin
  begin
    perform public.master_grant_entitlement(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','insumos',null,
      'cortesia','razon de cortesia valida', now()+interval '30 days', false);
  exception when others then
    raise exception 'TESTB1 FAIL: tomar a mano una fila de Stripe CANCELADA rebotó: %', sqlerrm;
  end;
  select * into r from public.org_entitlements
   where organization_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and kind='module' and key='insumos';
  if r.source <> 'master' then raise exception 'TESTB1 FAIL: source=% (esperado master)', r.source; end if;
  if r.stripe_subscription_id is not null or r.stripe_subscription_item_id is not null then
    raise exception 'TESTB1 FAIL: no se limpiaron los ids de Stripe (sub=%, item=%)',
      r.stripe_subscription_id, r.stripe_subscription_item_id;
  end if;
  raise notice 'TESTB1 PASS: fila de Stripe cancelada tomada a mano, ids limpiados';
end $$;

-- ============================================================ TEST B2 (activa → rebota)
delete from public.org_entitlements where organization_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
insert into public.org_entitlements(organization_id, kind, key, source, status, stripe_subscription_id)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','insumos','stripe','active','sub_a');
do $$
declare ok boolean := false;
begin
  begin
    perform public.master_grant_entitlement(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','module','insumos',null,
      'cortesia','razon de cortesia valida', now()+interval '30 days', false);
  exception when others then
    if sqlerrm like 'GRANT_STRIPE_OWNED%' then ok := true;
    else raise exception 'TESTB2 FAIL: mensaje inesperado: %', sqlerrm; end if;
  end;
  if not ok then raise exception 'TESTB2 FAIL: una fila de Stripe ACTIVA no rebotó'; end if;
  raise notice 'TESTB2 PASS: fila de Stripe activa sigue defendida';
end $$;

select '=== STRIPE-TAKEOVER TESTS PASSED ===' as result;
