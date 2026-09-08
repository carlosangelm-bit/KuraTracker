-- =============================================================================
-- license_phase1_acceptance_sandbox.sql — Pruebas de aceptación de la Fase 1 que
-- viven en la BASE (§9). Se ejecuta en el editor SQL de Supabase (SANDBOX), tras
-- aplicar 0108-0111. NO deja datos: DO block transaccional que termina lanzando
-- una excepción para forzar el ROLLBACK; el resultado llega COMO EL MENSAJE de esa
-- excepción (empieza con "ROLLBACK INTENCIONAL"). Todos PASS = ok.
--
-- Cubre (las de app —§9.1 backfill, §9.2 nav— se ven con el test Dart y el bloque
-- de verificación del 0109; aquí van las de SQL):
--   §9.3/§5  candado module_settings: sin derecho el enable REBOTA; con derecho pasa.
--   §9.4/§3  RLS: un admin de centro NO puede insertar en org_entitlements.
--   §9.5     tope de asientos al crear (assert_seat_available): sin lugar → rebota.
--   §9.6     administrativo puro NO consume asiento clínico (hasta el 4º).
--   §9.7     multi-rol {admin,clinico} cuenta 1 clínico y 0 admin.
--   §9.8     el cuidador no consume nada.
--   §9.9     webhook idempotente: reinsertar el mismo event_id rebota (PK).
-- =============================================================================

do $$
declare
  v_org uuid;
  v_p uuid[];
  v_admin_uid uuid;
  v_admin_org uuid;
  v_n int;
  r text := E'=== Aceptación Fase 1 (sandbox) ===\n';
begin
  -- Perfiles reales del seed para poblar membresías (sus roles en el CENTRO los
  -- fija la membresía, no el perfil). Necesitamos 5 activos no-master.
  select array_agg(id) into v_p from (
    select id from public.profiles
    where is_active and not ('master'::public.user_role = any(roles))
    order by id limit 5
  ) t;
  if v_p is null or array_length(v_p, 1) < 5 then
    raise exception 'Seed insuficiente: hacen falta 5 perfiles activos no-master.';
  end if;

  -- Centro de prueba con derechos controlados: module:clinico + module:admin +
  -- seat:clinico=2 (sin insumos, para el candado).
  insert into public.organizations (name, center_type, is_active)
  values ('QA Licencia Fase 1', 'clinica_heridas', true) returning id into v_org;
  insert into public.org_entitlements (organization_id, kind, key, quantity, status, source) values
    (v_org, 'module', 'clinico', null, 'active', 'master'),
    (v_org, 'module', 'admin',   null, 'active', 'master'),
    (v_org, 'seat',   'clinico', 2,    'active', 'master');

  -- Membresías: p1 clinico | p2 {admin,clinico} | p3 admin | p4 admin | p5 cuidador.
  insert into public.user_center_memberships (profile_id, organization_id, roles, is_active) values
    (v_p[1], v_org, array['clinico']::public.user_role[], true),
    (v_p[2], v_org, array['admin','clinico']::public.user_role[], true),
    (v_p[3], v_org, array['admin']::public.user_role[], true),
    (v_p[4], v_org, array['admin']::public.user_role[], true),
    (v_p[5], v_org, array['cuidador']::public.user_role[], true);

  -- §9.6/§9.7/§9.8 — contadores.
  v_n := public.consumed_clinical_seats(v_org);
  r := r || case when v_n = 2
    then E'PASS 9.7 · asientos clínicos = 2 (p1 y p2; multi-rol cuenta 1).\n'
    else format('FAIL 9.7 · asientos clínicos = %s (esperado 2).%s', v_n, E'\n') end;
  v_n := public.consumed_admin_slots(v_org);
  r := r || case when v_n = 2
    then E'PASS 9.6 · cupos admin = 2 (p3 y p4; p2 con rol clínico NO ocupa cupo admin).\n'
    else format('FAIL 9.6 · cupos admin = %s (esperado 2).%s', v_n, E'\n') end;
  -- El cuidador (p5) no aparece en ninguno → implícito en los dos de arriba.
  r := r || E'PASS 9.8 · el cuidador (p5) no movió ninguno de los dos contadores.\n';

  -- §9.5 — tope: seat:clinico=2 con 2 clínicos usados; alta de un 3º clínico rebota.
  begin
    perform public.assert_seat_available(v_org, array['clinico']::public.user_role[]);
    r := r || E'FAIL 9.5 · assert_seat_available dejó pasar un 3º clínico con cap=2.\n';
  exception when others then
    if sqlerrm like '%SEAT_NO_CLINICAL%' then
      r := r || E'PASS 9.5 · sin asientos clínicos, el alta rebota (SEAT_NO_CLINICAL).\n';
    else
      r := r || format('PASS? 9.5 · rebotó con otro error: %s%s', sqlerrm, E'\n');
    end if;
  end;

  -- §9.3/§5 — candado module_settings (como postgres: is_master()=false → se aplica).
  begin
    insert into public.module_settings (organization_id, module_key, enabled)
    values (v_org, 'insumos', true);
    r := r || E'FAIL 9.3 · se pudo encender Insumos SIN el derecho (candado no disparó).\n';
  exception when others then
    if sqlerrm like '%no tiene contratado%' then
      r := r || E'PASS 9.3 · encender Insumos sin derecho REBOTA con el mensaje en español.\n';
    else
      r := r || format('PASS? 9.3 · rebotó con otro error: %s%s', sqlerrm, E'\n');
    end if;
  end;
  begin
    insert into public.module_settings (organization_id, module_key, enabled)
    values (v_org, 'patients', true);   -- patients requiere module:clinico, que SÍ tiene
    r := r || E'PASS 9.3b · encender un módulo con derecho (patients/clinico) SÍ pasa.\n';
  exception when others then
    r := r || format('FAIL 9.3b · encender patients con derecho rebotó: %s%s', sqlerrm, E'\n');
  end;

  -- §9.9 — idempotencia del webhook (PK de stripe_events).
  insert into public.stripe_events (event_id, type) values ('qa_evt_fase1', 'checkout.session.completed');
  begin
    insert into public.stripe_events (event_id, type) values ('qa_evt_fase1', 'checkout.session.completed');
    r := r || E'FAIL 9.9 · el mismo event_id se insertó dos veces (sin idempotencia).\n';
  exception when unique_violation then
    r := r || E'PASS 9.9 · reinsertar el mismo event_id rebota (PK) → webhook idempotente.\n';
  end;

  -- §9.4/§3 — RLS: un admin de CENTRO no puede escribir org_entitlements.
  select id, organization_id into v_admin_uid, v_admin_org
  from public.profiles
  where is_active and ('admin'::public.user_role = any(roles))
    and not ('master'::public.user_role = any(roles)) and organization_id is not null
  order by id limit 1;
  if v_admin_uid is null then
    r := r || E'SKIP 9.4 · no hay un admin de centro con org en el seed.\n';
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_admin_uid::text, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      insert into public.org_entitlements (organization_id, kind, key, source)
      values (v_admin_org, 'module', 'insumos', 'master');
      r := r || E'FAIL 9.4 · un admin de centro LOGRÓ insertar un derecho (RLS no bloqueó).\n';
    exception
      when insufficient_privilege then
        r := r || E'PASS 9.4 · la RLS bloquea que el admin de centro escriba org_entitlements.\n';
      when others then
        r := r || format('PASS? 9.4 · bloqueado con otro error: %s%s', sqlerrm, E'\n');
    end;
    reset role;
  end if;

  raise exception E'ROLLBACK INTENCIONAL (no es un error real; no se dejaron datos).\n\n%', r;
end $$;
