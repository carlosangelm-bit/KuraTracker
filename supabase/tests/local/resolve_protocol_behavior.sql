-- ETAPA 3.a — Pruebas de CONDUCTA de resolve_protocol con salidas ESPERADAS escritas a mano
-- (no comparaciones contra Dart: cuando el Dart desaparezca, esto sigue siendo la cobertura).
--
-- CONDICIÓN 1 de la etapa 3.5 (demo): los casos de reglas PROPIAS NO viven aquí — viven en
-- supabase/tests/protocol_behavior_corpus.json, el MISMO archivo que lee la prueba del
-- resolvedor LOCAL DE DEMO (test/unit/resolve_protocol_demo_test.dart). Este script CARGA ese
-- corpus (lo dejó el runner en la tabla corpus_json) y lo corre contra el servidor. Si las dos
-- implementaciones divergen, una de las dos pruebas se pone roja — no hay dos copias del corpus.
-- Los bordes que la demo NO cubre (fuente CATÁLOGO + CONTEXTO) sí viven aquí, inline, porque el
-- resolvedor de demo solo resuelve reglas propias.
--
-- Se carga tras la cadena de migraciones (fixture + 0076/0077/0136..0139) y tras el \copy del
-- corpus a corpus_json. Corre en LOCAL (run_sql_tests.sh) y en CI (job sql_tests con postgres).

-- Helper: corre resolve_protocol y compara el régimen (category|producto|cantidad|fuente,
-- en ORDEN) contra el esperado; revienta si difiere. Lo usan los casos de CATÁLOGO (con fuente).
create or replace function pg_temp.chk(
  label text, expected text,
  p_org uuid, p_cats text[], p_area numeric, p_vol numeric,
  p_exu text, p_zone text, p_inf boolean, p_site uuid,
  p_ck text default null, p_cv text default null
) returns void language plpgsql as $$
declare got text;
begin
  select coalesce(string_agg(
           t.category || '|' || t.name || '|' ||
           to_char(round(t.quantity, 3), 'FM990.000') || '|' || t.source,
           ', ' order by t.ord), '')
    into got
  from public.resolve_protocol(p_org, p_cats, p_area, p_vol, p_exu, p_zone, p_inf, p_site, p_ck, p_cv)
       with ordinality as t(category, inventory_item_id, name, quantity, brand, alt_name, alt_brand, note_phrase, source, ord);
  if got is distinct from expected then
    raise exception 'BEHAVIOR FAIL [%]: esperado "%" pero fue "%"', label, expected, got;
  end if;
  raise notice 'BEHAVIOR PASS [%]', label;
end $$;

-- =============================================================================
-- Corpus PROPIO — cargado desde protocol_behavior_corpus.json (tabla corpus_json). Un centro
-- SIN Kura+ → camino 'propio'. La salida esperada del corpus es 'category|name|qty' SIN fuente
-- (en reglas propias la fuente es constante 'propio'); aquí se formatea igual para comparar.
-- =============================================================================
do $$
declare c jsonb;
begin
  select j into c from corpus_json;   -- una sola fila con todo el corpus
  if c is null then
    raise exception 'BEHAVIOR FAIL: corpus_json vacío (¿el runner no cargó el corpus?)';
  end if;

  insert into public.organizations (id, name)
    values ((c->>'org')::uuid, 'Behavior propio') on conflict do nothing;

  insert into public.inventory_items (id, organization_id, site_id, name)
    select (it->>'id')::uuid, (c->>'org')::uuid, (it->>'site')::uuid, it->>'name'
    from jsonb_array_elements(c->'items') it
    on conflict do nothing;

  insert into public.protocol_product_rules
    (id, organization_id, category, inventory_item_id, name, dimension, min_value, max_value,
     quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection)
    select (r->>'id')::uuid, (c->>'org')::uuid, r->>'category', (r->>'item')::uuid, r->>'name',
           r->>'dimension', (r->>'min')::numeric, (r->>'max')::numeric,
           r->>'quantity_mode', (r->>'quantity_value')::numeric, (r->>'sort_order')::int,
           r->'exudate_levels', r->'zone_groups', r->>'infection'
    from jsonb_array_elements(c->'rules') r
    on conflict do nothing;
end $$;

do $$
declare o uuid; s uuid; cs jsonb; got text; expected text;
begin
  select (j->>'org')::uuid, (j->>'site')::uuid into o, s from corpus_json;
  for cs in select value from corpus_json, jsonb_array_elements(j->'cases') as value loop
    select coalesce(string_agg(
             t.category || '|' || t.name || '|' || to_char(round(t.quantity, 3), 'FM990.000'),
             ', ' order by t.ord), '')
      into got
    from public.resolve_protocol(
           o,
           array(select jsonb_array_elements_text(cs->'categories')),
           (cs->>'area')::numeric, (cs->>'volume')::numeric,
           cs->>'exudate', cs->>'zone', (cs->>'infection')::boolean,
           s, null, null)
         with ordinality as t(category, inventory_item_id, name, quantity, brand, alt_name, alt_brand, note_phrase, source, ord);
    expected := cs->>'expected';
    if got is distinct from expected then
      raise exception 'BEHAVIOR FAIL [%]: esperado "%" pero fue "%"', cs->>'label', expected, got;
    end if;
    raise notice 'BEHAVIOR PASS [corpus %]', cs->>'label';
  end loop;
end $$;

-- FUENTE (6.1) del lado SERVIDOR: resolve_protocol debe devolver la columna `source` con los DOS
-- valores según el derecho. Aquí el camino PROPIO → 'propio'; los casos de catálogo de abajo →
-- 'kura'. Esto ata la garantía en el SERVIDOR (que la función DEVUELVE source), no solo en el
-- mapper de Dart: si una migración redefine resolve_protocol sin la columna, esta prueba revienta.
do $$
declare o uuid; s uuid;
begin
  select (j->>'org')::uuid, (j->>'site')::uuid into o, s from corpus_json;
  perform pg_temp.chk('own-source-propio', 'aposito|B|1.000|propio',
                      o, array['aposito'], 0, null, null, null, null, s);
end $$;

-- =============================================================================
-- Bordes que la demo NO corre (solo servidor): fuente CATÁLOGO, CONTEXTO e IDENTIDAD (etapa 5).
-- Cada escenario usa una CATEGORÍA distinta: el catálogo es GLOBAL y ahora las huérfanas con
-- nombre SALEN (item null), así que dos escenarios en la misma categoría se cruzarían.
-- =============================================================================
-- A) AUTOR (protocol:author). CONTEXTO + PROSA. Reglas sin identidad → item null, pero la PROSA
--    (name) es lo que ve el clínico, y chk compara category|name|qty|source. category = aposito.
-- §desacople: el autor edita el catálogo, pero RESUELVE con el catálogo solo si master prendió el
-- interruptor. Lo prendemos con sesión de MASTER (el candado de 0145 cubre INSERT+UPDATE, así que
-- un true sin master se rechaza). El caso 'autor con interruptor APAGADO → reglas propias' va abajo.
select set_config('test.uid', '30000000-0000-0000-0000-000000000000', false);  -- master
insert into public.organizations (id, name, protocol_resolves_from_catalog) values
  ('b0000000-0000-0000-0000-000000000002', 'Behavior author', true) on conflict do nothing;
select set_config('test.uid', '', false);
insert into public.org_entitlements (organization_id, kind, key, status, source) values
  ('b0000000-0000-0000-0000-000000000002', 'module', 'protocol:author', 'active', 'master') on conflict do nothing;
-- I1 solo aplica con etiología=pie_diabetico; I2 con context_value NULL = cualquier valor de piel.
insert into public.protocol_catalog_rules
  (id, category, name, dimension, quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection, context_kind, context_value)
values
  ('d0000000-0000-0000-0000-000000000001','aposito','I1','none','fixed',1,0,'[]','[]','any','etiologia','pie_diabetico'),
  ('d0000000-0000-0000-0000-000000000002','aposito','I2','none','fixed',1,1,'[]','[]','any','piel',null)
  on conflict do nothing;

do $$
declare a uuid := 'b0000000-0000-0000-0000-000000000002';
begin
  perform pg_temp.chk('ctx-etio-calza', 'aposito|I1|1.000|kura', a, array['aposito'], null,null,null,null,null,null, 'etiologia','pie_diabetico');
  perform pg_temp.chk('ctx-etio-otro',  '', a, array['aposito'], null,null,null,null,null,null, 'etiologia','quemaduras');
  perform pg_temp.chk('ctx-null',       '', a, array['aposito'], null,null,null,null,null,null, null,null);
  perform pg_temp.chk('ctx-value-any-dai','aposito|I2|1.000|kura', a, array['aposito'], null,null,null,null,null,null, 'piel','dai');
  perform pg_temp.chk('ctx-value-any-marsi','aposito|I2|1.000|kura', a, array['aposito'], null,null,null,null,null,null, 'piel','marsi');
end $$;

-- B) CONSUME (seat:protocolo) + IDENTIDAD que ATERRIZA. La regla del catálogo referencia el par
--    shopify; el consumidor tiene un insumo con ESE par → resolve enlaza el item (no null).
--    category = compresion (aislada de A). Fuente 'kura' (2.b: consume contra el catálogo).
insert into public.organizations (id, name) values
  ('b0000000-0000-0000-0000-000000000003', 'Behavior consume') on conflict do nothing;
insert into public.org_entitlements (organization_id, kind, key, quantity, status, source) values
  ('b0000000-0000-0000-0000-000000000003', 'seat', 'protocolo', 1, 'active', 'master') on conflict do nothing;
insert into public.inventory_items (id, organization_id, site_id, name, shopify_product_id, shopify_variant_id) values
  ('a0000000-0000-0000-0000-0000000000c3','b0000000-0000-0000-0000-000000000003',null,'I3-consumidor','SP-I3','')
  on conflict do nothing;
insert into public.protocol_catalog_rules
  (id, category, name, shopify_product_id, shopify_variant_id, dimension, quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection, context_kind, context_value)
values
  ('d0000000-0000-0000-0000-000000000003','compresion','I3-consumidor','SP-I3','','none','fixed',1,2,'[]','[]','any','piel',null)
  on conflict do nothing;

do $$
declare c uuid := 'b0000000-0000-0000-0000-000000000003'; got_item uuid;
begin
  perform pg_temp.chk('consume-identidad', 'compresion|I3-consumidor|1.000|kura', c, array['compresion'], null,null,null,null,null,null, 'piel','dai');
  -- y la IDENTIDAD ATERRIZÓ: el item resuelto NO es null (se enlazó al insumo del consumidor).
  select t.inventory_item_id into got_item
  from public.resolve_protocol(c, array['compresion'], null,null,null,null,null,null,'piel','dai') t limit 1;
  if got_item is distinct from 'a0000000-0000-0000-0000-0000000000c3' then
    raise exception 'BEHAVIOR FAIL [consume-identidad-item]: esperaba el insumo del consumidor, fue %', got_item;
  end if;
  raise notice 'BEHAVIOR PASS [consume-identidad-item]';
end $$;

-- C) HUÉRFANA CON NOMBRE: identidad que NO aterriza en el centro → la regla se resuelve IGUAL
--    (la prosa la ve el clínico) pero con item NULL, no se salta. category = descarga (aislada).
insert into public.protocol_catalog_rules
  (id, category, name, shopify_product_id, shopify_variant_id, dimension, quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection, context_kind, context_value)
values
  ('d0000000-0000-0000-0000-000000000005','descarga','Prod-sin-stock','SP-NOWHERE','','none','fixed',1,0,'[]','[]','any','evolucion','seguimiento')
  on conflict do nothing;

do $$
declare c uuid := 'b0000000-0000-0000-0000-000000000003'; got_item uuid; n int;
begin
  -- se DEVUELVE con su nombre (no vacío):
  perform pg_temp.chk('huerfana-con-nombre', 'descarga|Prod-sin-stock|1.000|kura', c, array['descarga'], null,null,null,null,null,null, 'evolucion','seguimiento');
  -- …y su item es NULL (no aterrizó en el centro):
  select t.inventory_item_id, count(*) over () into got_item, n
  from public.resolve_protocol(c, array['descarga'], null,null,null,null,null,null,'evolucion','seguimiento') t limit 1;
  if n <> 1 or got_item is not null then
    raise exception 'BEHAVIOR FAIL [huerfana-item-null]: esperaba 1 fila con item null, fue n=% item=%', n, got_item;
  end if;
  raise notice 'BEHAVIOR PASS [huerfana-item-null]';
end $$;

-- D) EL CASO KURA+ (§15 jerarquía): un centro AUTOR con el interruptor APAGADO Y CON seat:protocolo
--    vigente (cupo>=1) resuelve con sus REGLAS PROPIAS, no con el catálogo. Ser autor MANDA sobre
--    tener asiento: el asiento no le puede cambiar la fuente saltándose el interruptor. Es
--    exactamente Kura+ (tiene asientos para su personal). category = relleno_cavidad (aislada).
insert into public.organizations (id, name) values
  ('b0000000-0000-0000-0000-000000000006', 'Behavior author OFF') on conflict do nothing; -- switch = false (default)
insert into public.org_entitlements (organization_id, kind, key, quantity, status, source) values
  ('b0000000-0000-0000-0000-000000000006', 'module', 'protocol:author', null, 'active', 'master'),
  ('b0000000-0000-0000-0000-000000000006', 'seat',   'protocolo',       12,   'active', 'master')
  on conflict do nothing;
insert into public.inventory_items (id, organization_id, site_id, name) values
  ('a0000000-0000-0000-0000-0000000000d6','b0000000-0000-0000-0000-000000000006',null,'Propio-D6') on conflict do nothing;
insert into public.protocol_product_rules
  (id, organization_id, category, inventory_item_id, name, dimension, quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection)
values
  ('c6000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000006','relleno_cavidad','a0000000-0000-0000-0000-0000000000d6','Propio-D6','none','fixed',1,0,'[]','[]','any')
  on conflict do nothing;

do $$
declare a uuid := 'b0000000-0000-0000-0000-000000000006';
begin
  -- autor + seat vigente + interruptor APAGADO → reglas PROPIAS (no catálogo). Con la disyunción
  -- vieja, el asiento habría forzado el catálogo (vacío para relleno) y esto se pondría rojo.
  perform pg_temp.chk('kura+-autor-con-asiento-apagado', 'relleno_cavidad|Propio-D6|1.000|propio',
                      a, array['relleno_cavidad'], null,null,null,null,null,null, null,null);
end $$;

select '=== BEHAVIOR: ALL PASSED ===' as result;
