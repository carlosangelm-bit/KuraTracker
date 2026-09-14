-- =============================================================================
-- stripe_takeover_acceptance_sandbox.sql — Aceptación de 0133 (correcciones a la
-- etapa 1). Requiere un EVENTO de Stripe, así que el job migrations no las ve. Se
-- corre en el editor SQL del SANDBOX tras aplicar 0132 y 0133. DO block
-- transaccional que termina en ROLLBACK; el resultado llega como el mensaje de la
-- excepción "ROLLBACK INTENCIONAL". Todos PASS = ok.
--
-- No cambia de rol (corre como el owner del editor); is_master() se resuelve por el
-- jwt sembrado, y así apply_stripe_subscription_event (grant a service_role) también
-- es invocable. Cubre:
--   RT · ida y vuelta: otorgar module:insumos a mano, que Stripe TOME esa clave y
--        no reviente; la fila queda source='stripe' con los 4 campos manuales en
--        null y bitácora action='stripe_takeover'. (La prueba 1 de §6 cubría la otra
--        dirección: que el master NO pise a Stripe.)
--   B1 · tomar a mano una fila de Stripe CANCELADA pasa (cortesía a quien dejó de
--        pagar) y limpia los ids de Stripe.
--   B2 · tomar a mano una fila de Stripe ACTIVA sigue rebotando.
-- =============================================================================

do $$
declare
  v_master uuid;
  v_org uuid;
  v_lk text;
  r public.org_entitlements%rowtype;
  n int;
  ok boolean;
  rep text := E'=== Aceptación stripe-takeover (0133) ===\n';
begin
  select id into v_master from public.profiles
   where is_active and ('master'::public.user_role = any(roles)) order by id limit 1;
  if v_master is null then raise exception 'Seed insuficiente: no hay master activo.'; end if;

  insert into public.organizations (name, center_type, is_active)
  values ('QA Stripe-takeover 0133', 'clinica_heridas', true) returning id into v_org;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_master::text, 'role', 'authenticated')::text, true);

  select lookup_key into v_lk from public.billing_catalog
   where kind = 'module' and key = 'insumos' order by lookup_key limit 1;

  -- ------------------------------------------------------------------ TEST RT
  if v_lk is null then
    rep := rep || E'SKIP RT · no hay lookup_key de module:insumos en billing_catalog.\n';
  else
    perform public.master_grant_entitlement(
      v_org, 'module', 'insumos', null,
      'comercial', 'razon de prueba valida', now() + interval '30 days', false);
    -- Stripe toma la clave (si faltaran las 4 líneas de 0133, esto reventaría con el CHECK).
    perform public.apply_stripe_subscription_event(
      'evt_qa_takeover_' || v_org::text, 'customer.subscription.updated', v_org,
      'sub_qa_takeover', 'active', now() + interval '30 days',
      jsonb_build_array(jsonb_build_object(
        'lookup_key', v_lk, 'quantity', 0, 'subscription_item_id', 'si_qa', 'unit_amount', null)));
    select * into r from public.org_entitlements
     where organization_id = v_org and kind = 'module' and key = 'insumos';
    select count(*) into n from public.org_entitlement_log
     where organization_id = v_org and kind = 'module' and key = 'insumos' and action = 'stripe_takeover';
    if r.source = 'stripe' and r.grant_type is null and r.reason is null
       and r.granted_by is null and not r.is_permanent and n >= 1 then
      rep := rep || E'PASS RT · Stripe tomó la clave sin reventar; campos manuales en null; bitácora ok.\n';
    else
      rep := rep || format('FAIL RT · source=%s grant_type=%s is_permanent=%s takeover_logs=%s%s',
        r.source, r.grant_type, r.is_permanent, n, E'\n');
    end if;
  end if;

  -- ------------------------------------------------------------------ TEST B1
  delete from public.org_entitlements where organization_id = v_org;
  update public.organizations set stripe_subscription_id = null where id = v_org;
  insert into public.org_entitlements (organization_id, kind, key, source, status,
    stripe_subscription_id, stripe_subscription_item_id)
  values (v_org, 'module', 'insumos', 'stripe', 'canceled', 'sub_c', 'si_c');
  ok := true;
  begin
    perform public.master_grant_entitlement(
      v_org, 'module', 'insumos', null,
      'cortesia', 'razon de cortesia valida', now() + interval '30 days', false);
  exception when others then
    ok := false;
    rep := rep || format('FAIL B1 · tomar a mano una fila CANCELADA de Stripe rebotó: %s%s', sqlerrm, E'\n');
  end;
  if ok then
    select * into r from public.org_entitlements
     where organization_id = v_org and kind = 'module' and key = 'insumos';
    if r.source = 'master' and r.stripe_subscription_id is null
       and r.stripe_subscription_item_id is null then
      rep := rep || E'PASS B1 · fila de Stripe cancelada tomada a mano; ids de Stripe limpiados.\n';
    else
      rep := rep || format('FAIL B1 · source=%s sub=%s item=%s%s',
        r.source, r.stripe_subscription_id, r.stripe_subscription_item_id, E'\n');
    end if;
  end if;

  -- ------------------------------------------------------------------ TEST B2
  delete from public.org_entitlements where organization_id = v_org;
  insert into public.org_entitlements (organization_id, kind, key, source, status, stripe_subscription_id)
  values (v_org, 'module', 'insumos', 'stripe', 'active', 'sub_a');
  ok := false;
  begin
    perform public.master_grant_entitlement(
      v_org, 'module', 'insumos', null,
      'cortesia', 'razon de cortesia valida', now() + interval '30 days', false);
  exception when others then
    if sqlerrm like 'GRANT_STRIPE_OWNED%' then ok := true;
    else rep := rep || format('FAIL B2 · mensaje inesperado: %s%s', sqlerrm, E'\n'); end if;
  end;
  rep := rep || case when ok
    then E'PASS B2 · fila de Stripe ACTIVA sigue defendida.\n'
    else E'FAIL B2 · una fila de Stripe activa no rebotó.\n' end;

  raise exception E'ROLLBACK INTENCIONAL (no es un error real; no se dejaron datos).\n\n%', rep;
end $$;
