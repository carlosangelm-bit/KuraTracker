-- ETAPA 5 — verificación de la SIEMBRA. Corre DESPUÉS de 0141 (el arnés lo carga al final).
-- Una siembra que corre a medias se ve idéntica a una que no corrió: por eso no basta con que
-- 0141 no reviente. Un centro CONSUMIDOR debe resolver contra el catálogo recién sembrado y
-- DEVOLVER filas — si no, la fuente quedó apagada o la siembra quedó incompleta, y sería un
-- vacío silencioso en producción (justo lo que esta etapa existe para cerrar).
do $$
declare n_rules int; n_regimen int;
begin
  -- (1) la siembra dejó las 35 (o más) reglas Kura+.
  select count(*) into n_rules
  from public.protocol_catalog_rules
  where id >= 'd1000000-0000-0000-0000-000000000000'::uuid
    and id <= 'd1000000-0000-0000-0000-0000000000ff'::uuid;
  if n_rules < 35 then
    raise exception 'SEED FAIL: se esperaban >=35 reglas Kura+ sembradas, hay %', n_rules;
  end if;

  -- (2) un centro CONSUMIDOR (seat:protocolo, el b0..03 del arnés de conducta) resuelve un estado
  --     REAL de la matriz y recibe régimen. proteccion_piel + etiologia/lpp existe en las 35
  --     (Linovera). Cero filas aquí = siembra a medias o fuente apagada; NO un vacío legítimo.
  select count(*) into n_regimen
  from public.resolve_protocol(
    'b0000000-0000-0000-0000-000000000003', array['proteccion_piel'],
    null, null, null, null, null, null, 'etiologia', 'lpp')
  where source = 'kura';
  if n_regimen < 1 then
    raise exception 'SEED FAIL: el consumidor no recibió régimen del catálogo sembrado (0 filas) — siembra a medias o fuente apagada';
  end if;

  raise notice 'SEED PASS: % reglas Kura+ sembradas; el consumidor resuelve y devuelve % fila(s)', n_rules, n_regimen;
end $$;

select '=== SEED VERIFY: ALL PASSED ===' as result;
