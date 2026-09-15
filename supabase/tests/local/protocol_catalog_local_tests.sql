-- Pruebas locales de 0136+0137 (Matriz del protocolo, etapa 1). Se corren tras cargar el
-- fixture + 0076 + 0077 + 0136 + 0137 en un Postgres desechable (run_protocol_catalog.sh).
-- Verifican el CANDADO (RLS por admin + protocol:author) y la GUARDA DE DERIVA de esquemas.

grant select, insert, update, delete on public.protocol_catalog_rules to authenticated;

-- =============================================================================
-- TEST 1/2/3 — Candado por ROL, no solo por organización (corrección A de 0137). Todo en
-- una transacción que ABORTA. La RLS decide QUÉ filas ve cada quien; el grant es parejo.
-- =============================================================================
begin;
  -- Siembra como postgres (dueño → salta RLS): el catálogo TIENE una fila.
  insert into public.protocol_catalog_rules (category) values ('aposito');

  -- TEST1 — clínico de un centro SIN protocol:author (tiene module:admin/insumos) → 0 filas.
  set local test.uid = '22222222-2222-2222-2222-222222222222';
  set local role authenticated;
  do $$
  declare n int;
  begin
    select count(*) into n from public.protocol_catalog_rules;
    if n <> 0 then raise exception 'TEST1 FAIL: sin protocol:author vio % fila(s)', n; end if;
    raise notice 'TEST1 PASS: sin protocol:author, 0 filas (habiendo filas)';
  end $$;
  reset role;

  -- Se otorga protocol:author AL CENTRO (nivel organización).
  insert into public.org_entitlements (organization_id, kind, key, status, source)
    values ('11111111-1111-1111-1111-111111111111', 'module', 'protocol:author', 'active', 'master');

  -- TEST2 — el MISMO clínico (NO admin) del centro CON protocol:author: 0 filas y su INSERT
  -- es RECHAZADO. El derecho vive en la org, pero la autoría es del admin (corrección A).
  set local test.uid = '22222222-2222-2222-2222-222222222222';
  set local role authenticated;
  do $$
  declare n int;
  begin
    select count(*) into n from public.protocol_catalog_rules;
    if n <> 0 then raise exception 'TEST2a FAIL: no-admin CON author vio % fila(s)', n; end if;
    begin
      insert into public.protocol_catalog_rules (category) values ('intento_no_admin');
      raise exception 'TEST2b FAIL: el INSERT del no-admin NO fue rechazado';
    exception when insufficient_privilege then
      raise notice 'TEST2 PASS: no-admin con author → 0 filas y su INSERT rechazado';
    end;
  end $$;
  reset role;

  -- TEST3 — control positivo: el ADMIN del MISMO centro SÍ lee y SÍ escribe.
  set local test.uid = '33333333-3333-3333-3333-333333333333';
  set local role authenticated;
  do $$
  declare n int;
  begin
    select count(*) into n from public.protocol_catalog_rules;
    if n < 1 then raise exception 'TEST3a FAIL: admin con author no vio filas (vio %)', n; end if;
    insert into public.protocol_catalog_rules (category) values ('relleno');  -- debe pasar
    raise notice 'TEST3 PASS: admin con author lee y escribe el catálogo';
  end $$;
  reset role;
rollback;

-- =============================================================================
-- TEST 5 — Vigencia con asimetría por origen (corrección C). Se prueba el helper DIRECTO
-- por auth.uid (mira la vigencia, no la visibilidad de filas). Tres centros:
--   A master sin fecha → ABRE ; B master vencido → CIERRA ; C stripe vencido activo → ABRE.
-- =============================================================================
do $$
declare a boolean; b boolean; c boolean;
begin
  perform set_config('test.uid', '4a000000-0000-0000-0000-000000000000', true);
  a := public.current_org_has_protocol_author();
  perform set_config('test.uid', '5a000000-0000-0000-0000-000000000000', true);
  b := public.current_org_has_protocol_author();
  perform set_config('test.uid', '6a000000-0000-0000-0000-000000000000', true);
  c := public.current_org_has_protocol_author();
  if a is not true then raise exception 'TEST5 FAIL: master sin fecha debería ABRIR'; end if;
  if b is not false then raise exception 'TEST5 FAIL: master VENCIDO debería CERRAR'; end if;
  if c is not true then raise exception 'TEST5 FAIL: stripe vencido+activo debería ABRIR (ignora fecha)'; end if;
  raise notice 'TEST5 PASS: master sin fecha abre, master vencido cierra, stripe vencido abre';
  perform set_config('test.uid', '', true);
end $$;

-- =============================================================================
-- TEST 6 — Cambio de conducta de 1.5.b: encender un módulo respeta el VENCIMIENTO. Un
-- centro con prueba VENCIDA (module:clinico master, fecha pasada) ya NO puede; uno vigente sí.
-- El trigger se dispara aunque el actor sea postgres; is_master() se lee del GUC (no master).
-- =============================================================================
create trigger trg_zz_enforce_module_requires_entitlement
  before insert or update on public.module_settings
  for each row execute function public.enforce_module_requires_entitlement();
set test.uid = '22222222-2222-2222-2222-222222222222';  -- no master
do $$
begin
  begin
    insert into public.module_settings (organization_id, module_key, enabled)
      values ('77777777-7777-7777-7777-777777777777', 'insumos', true);
    raise exception 'TEST6a FAIL: la prueba VENCIDA pudo encender el módulo (hoy sí puede)';
  exception when others then
    if sqlerrm like '%no tiene contratado el módulo%'
      then raise notice 'TEST6a PASS: prueba vencida NO puede encender el módulo';
      else raise; end if;
  end;
  insert into public.module_settings (organization_id, module_key, enabled)
    values ('88888888-8888-8888-8888-888888888888', 'insumos', true);
  raise notice 'TEST6b PASS: centro vigente sí enciende el módulo';
end $$;
select set_config('test.uid', '', false);

-- =============================================================================
-- TEST 7 — GUARDA 1.5.d. Derivada del catálogo de Postgres (pg_proc): ninguna función que
-- consulte la VIGENCIA de org_entitlements (menciona current_period_end o status='active')
-- puede hacerlo FUERA de org_entitlement_vigente. Excepciones enumeradas: la propia
-- definición + escritores/contadores (referencian status por otra razón, no por gating).
-- Así una CUARTA definición no puede nacer en silencio.
-- =============================================================================
do $$
declare rogue text;
begin
  select string_agg(p.proname, ', ') into rogue
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosrc ~ 'org_entitlements'
    and (p.prosrc ~ 'current_period_end' or p.prosrc ~ 'status\s*=\s*''active''')
    and p.prosrc !~ 'org_entitlement_vigente'
    and p.proname not in (
      'org_entitlement_vigente',            -- la definición ÚNICA
      'master_grant_entitlement',           -- ESCRIBE status (RPC master)
      'master_revoke_entitlement',          -- ESCRIBE status
      'apply_stripe_subscription_event',    -- ESCRIBE status (webhook)
      'consumed_seat_demand',               -- CUENTA asientos activos
      'create_trial_organization'           -- SIEMBRA derechos de prueba
    );
  if rogue is not null then
    raise exception 'GUARDA 1.5.d FAIL: vigencia re-definida fuera de org_entitlement_vigente: %', rogue;
  end if;
  raise notice 'GUARDA 1.5.d (TEST7) PASS: la vigencia solo vive en org_entitlement_vigente';
end $$;

-- =============================================================================
-- TEST 4 — Guarda de deriva (15.1.d). Derivada del catálogo de Postgres, no una lista a
-- mano: toda columna de protocol_product_rules (salvo organization_id) debe existir en
-- protocol_catalog_rules con el MISMO tipo, y al revés.
-- =============================================================================
do $$
declare
  falta text;
begin
  select string_agg(format('%s (%s)', c.column_name, c.data_type), ', ')
    into falta
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'protocol_product_rules'
    and c.column_name <> 'organization_id'
    and not exists (
      select 1 from information_schema.columns k
      where k.table_schema = 'public' and k.table_name = 'protocol_catalog_rules'
        and k.column_name = c.column_name and k.data_type = c.data_type
    );
  if falta is not null then
    raise exception 'TEST4 FAIL (deriva): en product pero ausente/distinta en catalog: %', falta;
  end if;

  select string_agg(format('%s (%s)', k.column_name, k.data_type), ', ')
    into falta
  from information_schema.columns k
  where k.table_schema = 'public' and k.table_name = 'protocol_catalog_rules'
    and not exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = 'protocol_product_rules'
        and c.column_name = k.column_name and c.data_type = k.data_type
    );
  if falta is not null then
    raise exception 'TEST4 FAIL (deriva): en catalog pero ausente/distinta en product: %', falta;
  end if;

  raise notice 'TEST4 PASS: esquemas en paridad columna a columna (salvo organization_id)';
end $$;

select '=== ALL TESTS PASSED ===' as result;
