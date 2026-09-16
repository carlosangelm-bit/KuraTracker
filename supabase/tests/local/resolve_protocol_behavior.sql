-- ETAPA 3.a — Pruebas de CONDUCTA de resolve_protocol con salidas ESPERADAS escritas a mano
-- (no comparaciones contra Dart: cuando el Dart desaparezca, esto sigue siendo la cobertura).
-- Reusa el corpus de los 17 casos de paridad (hoy afirmaban SQL==Dart; ahora "SQL devuelve
-- EXACTAMENTE esto") + los bordes que la paridad no cubre: contexto y la fuente CATÁLOGO.
-- Se carga tras la cadena de migraciones (fixture + 0076/0077/0136..0139). Corre en LOCAL
-- (run_resolve_protocol_behavior.sh) y en CI (job sql_tests con servicio postgres).

-- Helper: corre resolve_protocol y compara el régimen (category|producto|cantidad|fuente,
-- en ORDEN) contra el esperado; revienta si difiere.
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
-- Corpus PROPIO (protocol_product_rules): un centro SIN Kura+ → camino 'propio'.
-- =============================================================================
insert into public.organizations (id, name) values
  ('b0000000-0000-0000-0000-000000000001', 'Behavior propio') on conflict do nothing;
-- Inventario: A..H en el sitio S1; Z en OTRO sitio (huérfana por sitio).
insert into public.inventory_items (id, organization_id, site_id, name) values
  ('a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000051','A'),
  ('a0000000-0000-0000-0000-00000000000b','b0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000051','B'),
  ('a0000000-0000-0000-0000-00000000000c','b0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000051','C'),
  ('a0000000-0000-0000-0000-00000000000d','b0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000051','D'),
  ('a0000000-0000-0000-0000-00000000000e','b0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000051','E'),
  ('a0000000-0000-0000-0000-00000000000f','b0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000051','F'),
  ('a0000000-0000-0000-0000-000000000010','b0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000051','G'),
  ('a0000000-0000-0000-0000-000000000011','b0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000051','H'),
  ('a0000000-0000-0000-0000-0000000000ff','b0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000052','Z')
  on conflict do nothing;
-- Reglas (sort_order define el orden y el desempate del dedup; priority NO desempata).
insert into public.protocol_product_rules
  (id, organization_id, category, inventory_item_id, name, dimension, min_value, max_value, quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection)
values
  ('c0000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-000000000001','aposito','a0000000-0000-0000-0000-00000000000a','A','none',null,null,'fixed',1,0,'[]','[]','any'),
  ('c0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','aposito','a0000000-0000-0000-0000-00000000000b','B','area',0,10,'fixed',1,1,'[]','[]','any'),
  ('c0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000001','aposito','a0000000-0000-0000-0000-00000000000c','C','area',10,null,'fixed',1,2,'[]','[]','any'),
  ('c0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000001','aposito','a0000000-0000-0000-0000-000000000011','H','none',null,null,'fixed',1,3,'["abundante"]','[]','any'),
  ('c0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000001','aposito','a0000000-0000-0000-0000-00000000000a','A','area',0,10,'fixed',1,4,'["abundante"]','[]','any'),
  ('c0000000-0000-0000-0000-000000000005','b0000000-0000-0000-0000-000000000001','limpieza','a0000000-0000-0000-0000-00000000000f','F','none',null,null,'fixed',1,5,'[]','[]','any'),
  ('c0000000-0000-0000-0000-000000000006','b0000000-0000-0000-0000-000000000001','limpieza','a0000000-0000-0000-0000-000000000010','G','none',null,null,'fixed',1,6,'[]','[]','any'),
  ('c0000000-0000-0000-0000-000000000007','b0000000-0000-0000-0000-000000000001','relleno_cavidad','a0000000-0000-0000-0000-00000000000d','D','volume',0,5,'per_volume',0.5,7,'[]','[]','any'),
  ('c0000000-0000-0000-0000-000000000008','b0000000-0000-0000-0000-000000000001','relleno_cavidad','a0000000-0000-0000-0000-00000000000e','E','volume',5,null,'per_volume',0.5,8,'[]','[]','any'),
  ('c0000000-0000-0000-0000-000000000009','b0000000-0000-0000-0000-000000000001','relleno_cavidad','a0000000-0000-0000-0000-00000000000d','D','volume',0,5,'fixed',9,9,'[]','[]','any'),
  ('c0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-000000000001','aposito','a0000000-0000-0000-0000-000000000010','G','none',null,null,'fixed',1,10,'[]','["sacro_gluteo"]','yes'),
  ('c0000000-0000-0000-0000-00000000000b','b0000000-0000-0000-0000-000000000001','aposito','a0000000-0000-0000-0000-0000000000ff','Z','area',0,10,'fixed',1,11,'[]','[]','any')
  on conflict do nothing;

do $$
declare o uuid := 'b0000000-0000-0000-0000-000000000001';
        s uuid := '50000000-0000-0000-0000-000000000051';
begin
  -- Los 17 casos, con salida ESPERADA a mano (fuente 'propio').
  perform pg_temp.chk('area-borde-inf', 'aposito|B|1.000|propio', o, array['aposito'], 0, null, null, null, null, s);
  perform pg_temp.chk('area-dentro',    'aposito|B|1.000|propio', o, array['aposito'], 5, null, null, null, null, s);
  perform pg_temp.chk('area-borde-sup', 'aposito|C|1.000|propio', o, array['aposito'], 10, null, null, null, null, s);
  perform pg_temp.chk('area-just-antes','aposito|B|1.000|propio', o, array['aposito'], 9.99, null, null, null, null, s);
  perform pg_temp.chk('area-grande',    'aposito|C|1.000|propio', o, array['aposito'], 50, null, null, null, null, s);
  perform pg_temp.chk('area-null',      'aposito|A|1.000|propio', o, array['aposito'], null, null, null, null, null, s);
  perform pg_temp.chk('area+exud-spec2','aposito|A|1.000|propio', o, array['aposito'], 5, null, 'abundante', null, null, s);
  perform pg_temp.chk('exudado-solo',   'aposito|H|1.000|propio', o, array['aposito'], null, null, 'abundante', null, null, s);
  perform pg_temp.chk('exudado-otro',   'aposito|A|1.000|propio', o, array['aposito'], null, null, 'escaso', null, null, s);
  perform pg_temp.chk('zona+infec-spec2','aposito|G|1.000|propio', o, array['aposito'], null, null, null, 'sacro_gluteo', true, s);
  perform pg_temp.chk('zona-sin-infec', 'aposito|A|1.000|propio', o, array['aposito'], null, null, null, 'sacro_gluteo', false, s);
  perform pg_temp.chk('limpieza-empate','limpieza|F|1.000|propio, limpieza|G|1.000|propio', o, array['limpieza'], null, null, null, null, null, s);
  perform pg_temp.chk('relleno-borde-inf','relleno_cavidad|D|0.000|propio', o, array['relleno_cavidad'], null, 0, null, null, null, s);
  perform pg_temp.chk('relleno-borde-sup','relleno_cavidad|E|2.500|propio', o, array['relleno_cavidad'], null, 5, null, null, null, s);
  perform pg_temp.chk('relleno-dentro', 'relleno_cavidad|D|1.500|propio', o, array['relleno_cavidad'], null, 3, null, null, null, s);
  perform pg_temp.chk('multi-cat',
    'aposito|A|1.000|propio, limpieza|F|1.000|propio, limpieza|G|1.000|propio, relleno_cavidad|D|1.000|propio',
    o, array['aposito','limpieza','relleno_cavidad'], 5, 2, 'abundante', null, null, s);
  perform pg_temp.chk('cat-inexistente','', o, array['desbridamiento'], 5, null, null, null, null, s);
end $$;

-- =============================================================================
-- Bordes que la paridad NO cubre (Dart tampoco): fuente CATÁLOGO + CONTEXTO.
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
