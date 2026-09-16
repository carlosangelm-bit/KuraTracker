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
-- TEST 8 — 2.d (el punto entero de la etapa): un centro que CONSUME Kura+ (seat:protocolo)
-- recibe su régimen de resolve_protocol, PERO un SELECT directo a protocol_catalog_rules le
-- da CERO filas. Las dos cosas EN LA MISMA SESIÓN, con la misma sesión.
-- =============================================================================
begin;
  -- Catálogo con una regla (postgres, salta RLS) que apunta al insumo del consumidor.
  insert into public.protocol_catalog_rules (category, inventory_item_id)
    values ('aposito', 'c0000000-0000-0000-0000-000000000001');
  set local test.uid = '9a000000-0000-0000-0000-000000000000';  -- admin del consumidor
  set local role authenticated;
  do $$
  declare n_regimen int; n_catalogo int;
  begin
    -- (a) recibe su régimen del catálogo (source='kura'):
    select count(*) into n_regimen
    from public.resolve_protocol(
      '99999999-9999-9999-9999-999999999999', array['aposito']::text[],
      null, null, null, null, null, null, null, null)
    where source = 'kura';
    if n_regimen < 1 then
      raise exception 'TEST8a FAIL: el consumidor no recibió su régimen del catálogo';
    end if;
    -- (b) pero NO puede LEER el catálogo (RLS: solo protocol:author):
    select count(*) into n_catalogo from public.protocol_catalog_rules;
    if n_catalogo <> 0 then
      raise exception 'TEST8b FAIL: el consumidor LEYÓ el catálogo (% filas)', n_catalogo;
    end if;
    raise notice 'TEST8 PASS: consume recibe su régimen del catálogo y NO puede leerlo (0 filas)';
  end $$;
  reset role;
rollback;

-- =============================================================================
-- TEST 9 — 2.e huérfanas: el reporte de huérfanas del CATÁLOGO SOLO lo ve protocol:author;
-- a un consumidor no se le filtra por ahí lo que no ve por la puerta.
-- =============================================================================
begin;
  insert into public.protocol_catalog_rules (category, inventory_item_id) values ('aposito', null);
  -- author (44444444 tiene protocol:author) VE la huérfana:
  set local test.uid = '4a000000-0000-0000-0000-000000000000';
  set local role authenticated;
  do $$ declare n int; begin
    select count(*) into n from public.resolve_protocol_orphans('44444444-4444-4444-4444-444444444444', null);
    if n < 1 then raise exception 'TEST9a FAIL: el author no vio la huérfana del catálogo'; end if;
    raise notice 'TEST9a PASS: author ve las huérfanas del catálogo';
  end $$;
  reset role;
  -- consumidor (99999999, sin author) NO ve nada por el reporte:
  set local test.uid = '9a000000-0000-0000-0000-000000000000';
  set local role authenticated;
  do $$ declare n int; begin
    select count(*) into n from public.resolve_protocol_orphans('99999999-9999-9999-9999-999999999999', null);
    if n <> 0 then raise exception 'TEST9b FAIL: el consumidor vio % huérfana(s) del catálogo', n; end if;
    raise notice 'TEST9b PASS: al consumidor no se le filtran las huérfanas del catálogo';
  end $$;
  reset role;
rollback;

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

-- =============================================================================
-- TEST 10 — GUARDA ENUMERADA de la AUTORIDAD del catálogo (6.2). "¿Quién puede ver/editar el
-- catálogo?" debe tener UNA respuesta: current_user_can_author_catalog(). Derivada del catálogo
-- de Postgres, no de una lista a mano: (a) toda policy sobre protocol_catalog_rules deriva de la
-- autoridad; (b) ninguna función que toque protocol_catalog_rules chequea rol/derecho de autoría
-- (is_admin | is_master | current_org_has_protocol_author) FUERA de la autoridad. Así una CUARTA
-- puerta no nace en silencio (el tablero mudo que originó esto).
-- =============================================================================
do $$
declare rogue text;
begin
  -- (a) policies del catálogo que NO derivan de la autoridad.
  select string_agg(polname, ', ') into rogue
  from pg_policy p join pg_class c on c.oid = p.polrelid
  where c.relname = 'protocol_catalog_rules'
    and ( coalesce(pg_get_expr(p.polqual, p.polrelid), '')       not like '%current_user_can_author_catalog%'
       or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')  not like '%current_user_can_author_catalog%' );
  if rogue is not null then
    raise exception 'GUARDA 6.2 FAIL: policy del catálogo no deriva de la autoridad: %', rogue;
  end if;

  -- (b) funciones que tocan el catálogo y chequean rol/autoría fuera de la autoridad única.
  select string_agg(pr.proname, ', ') into rogue
  from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
  where n.nspname = 'public'
    and pr.prosrc ~ 'protocol_catalog_rules'
    and (pr.prosrc ~ 'is_admin' or pr.prosrc ~ 'is_master' or pr.prosrc ~ 'current_org_has_protocol_author')
    and pr.prosrc !~ 'current_user_can_author_catalog'
    and pr.proname not in (
      'current_user_can_author_catalog'   -- la definición ÚNICA
    );
  if rogue is not null then
    raise exception 'GUARDA 6.2 FAIL: función chequea autoría del catálogo fuera de current_user_can_author_catalog: %', rogue;
  end if;
  raise notice 'TEST10 PASS: la autoridad del catálogo vive solo en current_user_can_author_catalog';
end $$;

-- =============================================================================
-- TEST 11 — el tablero mudo, cerrado. Un miembro del centro author SIN rol admin (4b) ya NO
-- recibe el reporte de huérfanas: concuerda con la RLS (que también le deja la tabla vacía). Un
-- admin del mismo centro (4a) sí. Las tres puertas concuerdan; sin rol → dicho por igual (0/0),
-- no vacío-y-lleno.
-- =============================================================================
begin;
  insert into public.protocol_catalog_rules (category) values ('aposito'); -- huérfana (sin identidad)
  -- (a) no-admin del centro author: 0 huérfanas (antes: las recibía → tablero mudo).
  set local test.uid = '4b000000-0000-0000-0000-000000000000';
  set local role authenticated;
  do $$ declare n int; begin
    select count(*) into n from public.resolve_protocol_orphans('44444444-4444-4444-4444-444444444444', null);
    if n <> 0 then raise exception 'TEST11a FAIL: no-admin del centro author vio % huérfana(s)', n; end if;
    raise notice 'TEST11a PASS: no-admin author → 0 huérfanas (concuerda con la RLS)';
  end $$;
  reset role;
  -- (b) admin del mismo centro: sí ve la huérfana.
  set local test.uid = '4a000000-0000-0000-0000-000000000000';
  set local role authenticated;
  do $$ declare n int; begin
    select count(*) into n from public.resolve_protocol_orphans('44444444-4444-4444-4444-444444444444', null);
    if n < 1 then raise exception 'TEST11b FAIL: admin author no vio la huérfana (vio %)', n; end if;
    raise notice 'TEST11b PASS: admin author sí ve las huérfanas';
  end $$;
  reset role;
rollback;

select '=== ALL TESTS PASSED ===' as result;
