-- Pruebas locales de 0136 (Matriz del protocolo, etapa 1). Se corren tras cargar el
-- fixture + 0076 + 0077 + 0136 en un Postgres desechable (run_protocol_catalog.sh).
-- Verifican el CANDADO (RLS por protocol:author) y la GUARDA DE DERIVA de esquemas.

-- El rol authenticated necesita el grant de tabla (en Supabase lo dan por defecto; aquí
-- explícito). La RLS es la que decide QUÉ filas ve, no el grant.
grant select, insert, update, delete on public.protocol_catalog_rules to authenticated;

-- =============================================================================
-- TEST 1 — Candado: un miembro SIN protocol:author obtiene CERO filas, AUNQUE la tabla
-- tenga filas y aunque tenga otros módulos. Control positivo: con protocol:author, el
-- MISMO miembro sí las ve (un candado que bloquea a todos también "pasaría" el caso 0).
-- Todo dentro de una transacción que ABORTA (no ensucia nada).
-- =============================================================================
begin;
  -- Siembra como postgres (dueño → salta RLS): el catálogo TIENE una fila.
  insert into public.protocol_catalog_rules (category) values ('aposito');

  -- 1a — miembro clínico de un centro con module:admin/insumos pero SIN protocol:author.
  set local test.uid = '22222222-2222-2222-2222-222222222222';
  set local role authenticated;
  do $$
  declare n int;
  begin
    select count(*) into n from public.protocol_catalog_rules;
    if n <> 0 then
      raise exception 'TEST1a FAIL: miembro SIN protocol:author vio % fila(s)', n;
    end if;
    raise notice 'TEST1a PASS: 0 filas sin protocol:author (habiendo filas sembradas)';
  end $$;
  reset role;

  -- 1b — control positivo: se le otorga protocol:author a su centro; el MISMO miembro la ve.
  insert into public.org_entitlements (organization_id, kind, key, status, source)
    values ('11111111-1111-1111-1111-111111111111', 'module', 'protocol:author', 'active', 'master');
  set local role authenticated;
  do $$
  declare n int;
  begin
    select count(*) into n from public.protocol_catalog_rules;
    if n <> 1 then
      raise exception 'TEST1b FAIL: con protocol:author debería ver 1 fila, vio %', n;
    end if;
    raise notice 'TEST1b PASS: con protocol:author sí ve el catálogo (1 fila)';
  end $$;
  reset role;
rollback;

-- =============================================================================
-- TEST 2 — Guarda de deriva (15.1.d). Derivada del catálogo de Postgres, no una lista
-- a mano: toda columna de protocol_product_rules (salvo organization_id) debe existir en
-- protocol_catalog_rules con el MISMO tipo, y al revés. Si alguien agrega una columna a
-- una sola tabla, esto se cae.
-- =============================================================================
do $$
declare
  falta text;
begin
  -- product (salvo organization_id) → debe estar en catalog con igual tipo.
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
    raise exception 'TEST2 FAIL (deriva): en product pero ausente/distinta en catalog: %', falta;
  end if;

  -- catalog → debe estar en product con igual tipo (al revés).
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
    raise exception 'TEST2 FAIL (deriva): en catalog pero ausente/distinta en product: %', falta;
  end if;

  raise notice 'TEST2 PASS: esquemas en paridad columna a columna (salvo organization_id)';
end $$;

select '=== ALL TESTS PASSED ===' as result;
