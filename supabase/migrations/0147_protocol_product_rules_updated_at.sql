-- 0147_protocol_product_rules_updated_at.sql
-- La BASE es la dueña de updated_at en protocol_product_rules (las reglas PROPIAS del centro,
-- donde un centro escribe su propio protocolo). La tabla ya trae `updated_at timestamptz not
-- null default now()` (0076) para el INSERT, pero NO tenía trigger que lo avance en UPDATE, así
-- que el cliente lo mandaba a mano —y en HORA LOCAL (UTC−6) sobre un timestamptz, quedando ~6 h
-- antes que created_at (medido por Carlos: created_at 00:31 UTC vs updated_at 18:31 "local")—.
-- El arreglo correcto: que el cliente NO escriba updated_at y la base lo ponga. Se cuelga la
-- función reusable set_updated_at() (0002) como BEFORE UPDATE; saveProtocolProductRule deja de
-- escribir el campo (data_repository). Mismo patrón que la migración 0146 (el disparador
-- gemelo para el catálogo Kura+).

drop trigger if exists trg_protocol_product_rules_updated_at
  on public.protocol_product_rules;
create trigger trg_protocol_product_rules_updated_at
  before update on public.protocol_product_rules
  for each row execute function public.set_updated_at();
