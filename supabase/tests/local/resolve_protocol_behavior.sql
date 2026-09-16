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

-- =============================================================================
-- Bordes que la demo NO corre (solo servidor): fuente CATÁLOGO + CONTEXTO. Inline, con fuente.
-- =============================================================================
-- Centro AUTOR (protocol:author) con su inventario y reglas de catálogo con contexto.
insert into public.organizations (id, name) values
  ('b0000000-0000-0000-0000-000000000002', 'Behavior author') on conflict do nothing;
insert into public.org_entitlements (organization_id, kind, key, status, source) values
  ('b0000000-0000-0000-0000-000000000002', 'module', 'protocol:author', 'active', 'master') on conflict do nothing;
insert into public.inventory_items (id, organization_id, site_id, name) values
  ('a0000000-0000-0000-0000-00000000c1c1','b0000000-0000-0000-0000-000000000002',null,'I1'),
  ('a0000000-0000-0000-0000-00000000c2c2','b0000000-0000-0000-0000-000000000002',null,'I2')
  on conflict do nothing;
-- I1 solo aplica con etiología=pie_diabetico; I2 con context_value NULL = cualquier valor de piel.
insert into public.protocol_catalog_rules
  (id, category, inventory_item_id, name, dimension, quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection, context_kind, context_value)
values
  ('d0000000-0000-0000-0000-000000000001','aposito','a0000000-0000-0000-0000-00000000c1c1','I1','none','fixed',1,0,'[]','[]','any','etiologia','pie_diabetico'),
  ('d0000000-0000-0000-0000-000000000002','aposito','a0000000-0000-0000-0000-00000000c2c2','I2','none','fixed',1,1,'[]','[]','any','piel',null)
  on conflict do nothing;

do $$
declare a uuid := 'b0000000-0000-0000-0000-000000000002';
begin
  -- contexto que CALZA (etiología pie_diabetico) → I1, fuente 'kura'.
  perform pg_temp.chk('ctx-etio-calza', 'aposito|I1|1.000|kura', a, array['aposito'], null,null,null,null,null,null, 'etiologia','pie_diabetico');
  -- contexto de MISMO kind pero OTRO valor (quemaduras) → I1 no aplica; queda vacío.
  perform pg_temp.chk('ctx-etio-otro',  '', a, array['aposito'], null,null,null,null,null,null, 'etiologia','quemaduras');
  -- SIN contexto (null) → una regla con context_kind no-null NO aplica → vacío.
  perform pg_temp.chk('ctx-null',       '', a, array['aposito'], null,null,null,null,null,null, null,null);
  -- context_value NULL en la regla = CUALQUIER valor de ese kind → I2 con piel=dai.
  perform pg_temp.chk('ctx-value-any-dai','aposito|I2|1.000|kura', a, array['aposito'], null,null,null,null,null,null, 'piel','dai');
  perform pg_temp.chk('ctx-value-any-marsi','aposito|I2|1.000|kura', a, array['aposito'], null,null,null,null,null,null, 'piel','marsi');
end $$;

-- Centro que CONSUME (seat:protocolo) resuelve contra el catálogo → fuente 'kura' (2.b).
insert into public.organizations (id, name) values
  ('b0000000-0000-0000-0000-000000000003', 'Behavior consume') on conflict do nothing;
insert into public.org_entitlements (organization_id, kind, key, quantity, status, source) values
  ('b0000000-0000-0000-0000-000000000003', 'seat', 'protocolo', 1, 'active', 'master') on conflict do nothing;
-- El consumidor tiene su PROPIO insumo (id distinto) y una regla de catálogo que lo apunta.
-- (En la etapa 5 el catálogo referirá el producto por IDENTIDAD, no por el id de un centro;
-- aquí basta con que el join calce para probar la FUENTE del consumidor.)
insert into public.inventory_items (id, organization_id, site_id, name) values
  ('a0000000-0000-0000-0000-0000000000c3','b0000000-0000-0000-0000-000000000003',null,'I3-consumidor')
  on conflict do nothing;
insert into public.protocol_catalog_rules
  (id, category, inventory_item_id, name, dimension, quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection, context_kind, context_value)
values
  ('d0000000-0000-0000-0000-000000000003','aposito','a0000000-0000-0000-0000-0000000000c3','I3','none','fixed',1,2,'[]','[]','any','piel',null)
  on conflict do nothing;

do $$
declare c uuid := 'b0000000-0000-0000-0000-000000000003';
begin
  perform pg_temp.chk('consume-catalogo', 'aposito|I3-consumidor|1.000|kura', c, array['aposito'], null,null,null,null,null,null, 'piel','dai');
end $$;

select '=== BEHAVIOR: ALL PASSED ===' as result;
