-- Los tres rechazos de 0134 EJECUTADOS contra la base (no solo "la función existe"),
-- más el caso positivo. Cada test usa su propio centro/sitios para aislarse. Con
-- ON_ERROR_STOP=1, un FAIL corta el script.

-- Ids fijos por test (org / sitios).
--   test1: org 11.. , sitio 10..01
--   test2: org 22.. , sitios 20..01 / 20..02 , staff 2a
--   test3: org 33.. , sitios 30..01 / 30..02 , item it3
--   pos  : org 44.. , sitios 40..01 / 40..02

-- ============================ TEST 1: único sitio activo ======================
insert into public.sites(id, organization_id, is_active) values
  ('10000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', true);
do $$
declare ok boolean := false;
begin
  begin
    update public.sites set is_active = false
      where id = '10000000-0000-0000-0000-000000000001';
  exception when others then
    if sqlerrm like '%es el único activo del centro y toda consulta necesita un sitio%'
      then ok := true;
    else raise exception 'TEST1 FAIL: mensaje inesperado: %', sqlerrm; end if;
  end;
  if not ok then raise exception 'TEST1 FAIL: no rechazó el único sitio activo'; end if;
  raise notice 'TEST1 PASS (único sitio activo)';
end $$;

-- ============================ TEST 2: personal activo ========================
insert into public.sites(id, organization_id, is_active) values
  ('20000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', true),
  ('20000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', true);
insert into public.staff(id, primary_site_id, is_active) values
  ('2a000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', true);
do $$
declare ok boolean := false;
begin
  begin
    update public.sites set is_active = false
      where id = '20000000-0000-0000-0000-000000000001';
  exception when others then
    if sqlerrm like '%personas lo tienen como sitio principal. Reasígnalas en Personal%'
      then ok := true;
    else raise exception 'TEST2 FAIL: mensaje inesperado: %', sqlerrm; end if;
  end;
  if not ok then raise exception 'TEST2 FAIL: no rechazó por personal activo'; end if;
  raise notice 'TEST2 PASS (personal activo)';
end $$;

-- ============================ TEST 3: inventario <> 0 ========================
insert into public.sites(id, organization_id, is_active) values
  ('30000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', true),
  ('30000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', true);
insert into public.inventory_movements(id, site_id, inventory_item_id, delta) values
  ('3a000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001', 5);
do $$
declare ok boolean := false;
begin
  begin
    update public.sites set is_active = false
      where id = '30000000-0000-0000-0000-000000000001';
  exception when others then
    if sqlerrm like '%tiene existencias en inventario. Trasládalas o ajústalas a cero%'
      then ok := true;
    else raise exception 'TEST3 FAIL: mensaje inesperado: %', sqlerrm; end if;
  end;
  if not ok then raise exception 'TEST3 FAIL: no rechazó por existencias'; end if;
  raise notice 'TEST3 PASS (inventario distinto de cero)';
end $$;

-- ==================== CASO POSITIVO: ninguno de los tres =====================
-- Sitio 40..01: no es el único (40..02 activo), sin personal apuntándole, e inventario
-- con neto CERO (+5 / -5). Una guardia que bloquea todo TAMBIÉN reprobaría este.
insert into public.sites(id, organization_id, is_active) values
  ('40000000-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', true),
  ('40000000-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', true);
insert into public.staff(id, primary_site_id, is_active) values
  ('4a000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002', true);
insert into public.inventory_movements(id, site_id, inventory_item_id, delta) values
  ('4b000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
   'a4000000-0000-0000-0000-000000000001', 5),
  ('4b000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000001',
   'a4000000-0000-0000-0000-000000000001', -5);
do $$
begin
  update public.sites set is_active = false
    where id = '40000000-0000-0000-0000-000000000001';
  if (select is_active from public.sites
        where id = '40000000-0000-0000-0000-000000000001') then
    raise exception 'POS FAIL: el sitio válido NO se desactivó';
  end if;
  raise notice 'POS PASS (un sitio sin ninguno de los tres sí se desactiva)';
end $$;

select 'ALL TESTS PASSED' as result;
