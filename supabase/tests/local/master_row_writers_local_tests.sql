-- Verifica que CADA escritor de filas source='master' produce filas que pasan
-- ent_master_grant_shape (0132), EJECUTADO contra Postgres. Enumeración (§ del pedido):
--   1. backfill de 0114        → aquí (sus filas peladas rellenadas por 0132)
--   2. master_grant_entitlement (0132) → master_grants_local_tests.sql (run.sh)
--   3. toma de posesión Stripe  (0133) → stripe_takeover_local_tests.sql (run.sh)
--   4. create_trial_organization (0135) → aquí
-- La reja Dart (test/unit/master_row_writers_ratchet_test.dart) impide que aparezca un
-- 5º escritor sin enumerar.

-- WRITER 1 (0114): si 0132 se aplicó (lo hizo el run script), sus filas peladas quedaron
-- rellenadas; ninguna master sin grant_type debe sobrevivir.
do $$
declare v_bad int;
begin
  select count(*) into v_bad from public.org_entitlements
    where source = 'master' and grant_type is null;
  if v_bad > 0 then
    raise exception '0114 FAIL: % filas master sin grant_type tras 0132', v_bad;
  end if;
  raise notice '0114 PASS: las filas master del backfill cumplen el CHECK tras 0132';
end $$;

-- WRITER 4 (0135): create_trial_organization crea 7 filas master; el insert pasa el
-- CHECK (si no, 23514 abortaría la función).
select set_config('test.uid', '99999999-9999-9999-9999-999999999999', false);
do $$
declare v_org uuid; v_n int;
begin
  v_org := public.create_trial_organization(
    'Centro Prueba Harness', 'hospital', null, null, false, 30, 5, 5, true);
  select count(*) into v_n from public.org_entitlements
    where organization_id = v_org and source = 'master';
  if v_n <> 7 then
    raise exception '0135 FAIL: esperaba 7 filas master, hay %', v_n;
  end if;
  raise notice '0135 PASS: create_trial_organization crea 7 filas master válidas';
end $$;

select 'ALL WRITERS OK' as result;
