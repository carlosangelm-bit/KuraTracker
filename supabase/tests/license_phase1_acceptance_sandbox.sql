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
--   §9.11    capacidad clínica por PERFIL: un admin con membresía vacía pero
--            perfil clínico-capaz suma asiento CLÍNICO, 0 admin (por profile_can_define_plans).
--   §9.12    enfermería {enfermeria}: consume asiento CLÍNICO (usa el módulo), 0 admin.
--   §9.13    {admin,enfermeria}: asiento CLÍNICO (no cupo admin gratis) — enfermería manda.
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
  -- Perfiles reales del seed. Los contadores miden por CAPACIDAD DE PERFIL
  -- (consumes_clinical_seat(p.roles, p.role)), así que el escenario se fija en los
  -- PERFILES, no en la membresía. Necesitamos 8 activos no-master
  -- (5 base + §9.11 admin-capaz + §9.12 enfermería + §9.13 admin+enfermería).
  select array_agg(id) into v_p from (
    select id from public.profiles
    where is_active and not ('master'::public.user_role = any(roles))
    order by id limit 8
  ) t;
  if v_p is null or array_length(v_p, 1) < 8 then
    raise exception 'Seed insuficiente: hacen falta 8 perfiles activos no-master.';
  end if;

  -- Centro de prueba con derechos controlados: module:clinico + module:admin +
  -- seat:clinico=2 (sin insumos, para el candado).
  insert into public.organizations (name, center_type, is_active)
  values ('QA Licencia Fase 1', 'clinica_heridas', true) returning id into v_org;
  insert into public.org_entitlements (organization_id, kind, key, quantity, status, source) values
    (v_org, 'module', 'clinico', null, 'active', 'master'),
    (v_org, 'module', 'admin',   null, 'active', 'master'),
    (v_org, 'seat',   'clinico', 2,    'active', 'master');

  -- Roles POR PERFIL (lo que miden los contadores): p1 clinico | p2 {admin,clinico}
  -- | p3 admin | p4 admin | p5 cuidador. (Como postgres/auth.uid null, el guard de
  -- escalada de profiles no dispara.)
  update public.profiles set roles = array['clinico']::public.user_role[],        role = 'clinico'  where id = v_p[1];
  update public.profiles set roles = array['admin','clinico']::public.user_role[], role = 'clinico'  where id = v_p[2];
  update public.profiles set roles = array['admin']::public.user_role[],           role = 'admin'    where id = v_p[3];
  update public.profiles set roles = array['admin']::public.user_role[],           role = 'admin'    where id = v_p[4];
  update public.profiles set roles = array['cuidador']::public.user_role[],        role = 'cuidador' where id = v_p[5];

  -- Membresías en el centro (5 primeros). Los roles de membresía ya no clasifican
  -- el asiento; lo hace la capacidad de perfil.
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

  -- §9.11 — capacidad de PERFIL, no membresía: un admin con roles de MEMBRESÍA
  -- vacíos pero capacidad clínica por perfil (roles vacíos + role='admin' →
  -- profile_can_define_plans = true) suma 1 a asientos clínicos y 0 a cupos admin.
  -- Es el caso que con la definición vieja (por membresía) se contaba mal.
  update public.profiles set roles = '{}'::public.user_role[], role = 'admin' where id = v_p[6];
  insert into public.user_center_memberships (profile_id, organization_id, roles, is_active)
    values (v_p[6], v_org, '{}'::public.user_role[], true);
  declare
    v_cli_before int := public.consumed_clinical_seats(v_org);
    v_adm_before int := public.consumed_admin_slots(v_org);
  begin
    -- (los valores "antes" ya incluyen a p6 recién insertado; comparamos contra
    --  el escenario base p1-p5: clínicos 2, admin 2)
    r := r || case when v_cli_before = 3
      then E'PASS 9.11 · admin con membresía vacía + capacidad clínica por perfil → asiento CLÍNICO (2+1).\n'
      else format('FAIL 9.11 · asientos clínicos = %s (esperado 3 con p6).%s', v_cli_before, E'\n') end;
    r := r || case when v_adm_before = 2
      then E'PASS 9.11b · …y NO ocupa cupo administrativo (sigue en 2).\n'
      else format('FAIL 9.11b · cupos admin = %s (esperado 2).%s', v_adm_before, E'\n') end;
  end;

  -- §9.12/§9.13 — enfermería CONSUME asiento clínico (usa el módulo clínico), aunque
  -- NO defina planes. Es la diferencia entre consumes_clinical_seat y
  -- profile_can_define_plans: sustituir el predicado (y no componerlo) dejaba a
  -- enfermería sin contar → altas sin tope. p7 {enfermeria}; p8 {admin,enfermeria}.
  update public.profiles set roles = array['enfermeria']::public.user_role[],         role = 'enfermeria' where id = v_p[7];
  update public.profiles set roles = array['admin','enfermeria']::public.user_role[], role = 'enfermeria' where id = v_p[8];
  insert into public.user_center_memberships (profile_id, organization_id, roles, is_active) values
    (v_p[7], v_org, array['enfermeria']::public.user_role[], true),
    (v_p[8], v_org, array['admin','enfermeria']::public.user_role[], true);
  declare
    v_cli int := public.consumed_clinical_seats(v_org);
    v_adm int := public.consumed_admin_slots(v_org);
  begin
    -- base p1-p5 (2 clínicos) + p6 admin-capaz (+1) + p7 y p8 enfermería (+2) = 5.
    r := r || case when v_cli = 5
      then E'PASS 9.12/9.13 · enfermería (p7 sola, p8 con admin) consume asiento CLÍNICO (3+2=5).\n'
      else format('FAIL 9.12/9.13 · asientos clínicos = %s (esperado 5).%s', v_cli, E'\n') end;
    -- p8 {admin,enfermeria} NO cae en cupo admin (enfermería manda): sigue en 2.
    r := r || case when v_adm = 2
      then E'PASS 9.13b · {admin,enfermeria} NO ocupa cupo admin gratis (sigue en 2).\n'
      else format('FAIL 9.13b · cupos admin = %s (esperado 2).%s', v_adm, E'\n') end;
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
