-- WRITER: backfill de 0114. Inserta filas source='master' SIN grant_type/reason/
-- is_permanent, tal como 0114. Deben SOBREVIVIR a 0132, que las rellena (2.2) ANTES de
-- añadir ent_master_grant_shape (2.3). Si 0132 las rechazara al crear el CHECK, este
-- arnés fallaría al aplicar 0132 — que es exactamente la regresión que vigilamos.
insert into public.organizations (id, name) values
  ('b0000000-0000-4000-a000-000000000001', 'Centro 0114') on conflict do nothing;
insert into public.org_entitlements
  (organization_id, kind, key, quantity, status, current_period_end, source)
values
  ('b0000000-0000-4000-a000-000000000001', 'plan',   'basico',  null, 'active', null, 'master'),
  ('b0000000-0000-4000-a000-000000000001', 'module', 'clinico', null, 'active', null, 'master');
