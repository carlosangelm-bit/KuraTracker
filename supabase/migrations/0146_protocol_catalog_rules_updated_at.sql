-- 0146_protocol_catalog_rules_updated_at.sql
-- La BASE es la dueña de updated_at, como de created_at. La tabla ya trae
-- `updated_at timestamptz not null default now()` (0136) para el INSERT, pero NO
-- tenía trigger que lo avance en UPDATE, así que el cliente lo mandaba a mano —y lo
-- mandaba en HORA LOCAL (UTC−6) sobre un timestamptz, quedando 360 min antes que
-- created_at. El arreglo correcto (Carlos): que el cliente NO escriba updated_at y
-- la base lo ponga. Aquí se cuelga la función reusable set_updated_at() (0002) como
-- BEFORE UPDATE, y el cliente deja de escribir el campo (data_repository).

drop trigger if exists trg_protocol_catalog_rules_updated_at
  on public.protocol_catalog_rules;
create trigger trg_protocol_catalog_rules_updated_at
  before update on public.protocol_catalog_rules
  for each row execute function public.set_updated_at();
