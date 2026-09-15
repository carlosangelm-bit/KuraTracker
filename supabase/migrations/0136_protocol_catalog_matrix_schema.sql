-- =============================================================================
-- 0136_protocol_catalog_matrix_schema.sql — Matriz del protocolo · ETAPA 1 de 8
-- =============================================================================
-- Esquema y candado, NADA de conducta. El resolvedor de Dart sigue funcionando
-- igual sobre protocol_product_rules; esta migración solo AGREGA columnas (aditivo),
-- crea el catálogo del sistema (protocol_catalog_rules, VACÍO) y lo cierra con un
-- derecho nuevo (protocol:author). No otorga el derecho a nadie: eso va aparte, con
-- conocimiento de Carlos. La siembra del catálogo es la etapa 5. La retirada del
-- resolvedor de Dart es la etapa 3, solo con paridad probada.
--
-- Modelo completo: claude/matriz-del-protocolo-modelo-unico-spec.md (rev. 3).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 15.1.a — Columnas NUEVAS en protocol_product_rules (aditivas). Contexto (a qué
-- etiología/piel/evolución aplica), etiquetas de PROSA que no gobiernan nada, y
-- campos de producto en prosa (marca, alterno, frase de nota).
-- -----------------------------------------------------------------------------
alter table public.protocol_product_rules
  add column if not exists context_kind  text, -- etiologia | piel | evolucion | null (= todo)
  add column if not exists context_value text, -- pie_diabetico | quemaduras | desgarro | dai | mdrpi | marsi | seguimiento
  add column if not exists scale_label   text, -- PROSA, no gobierna nada
  add column if not exists trigger_label text, -- PROSA, no gobierna nada
  add column if not exists brand         text,
  add column if not exists alt_name      text,
  add column if not exists alt_brand     text,
  add column if not exists note_phrase   text;

-- -----------------------------------------------------------------------------
-- 15.1.b — protocol_catalog_rules: el catálogo Kura+. MISMA forma que
-- protocol_product_rules PERO SIN organization_id (es del sistema, no de un centro).
-- Tabla APARTE, no "filas con organization_id NULL": con tabla aparte la política de
-- lectura es una sola y ninguna fila global se cuela por la política por organización
-- de protocol_product_rules. Se crea VACÍA (la siembra es la etapa 5).
-- La guarda de deriva (test 15.1.d) exige que las columnas coincidan 1:1 (salvo
-- organization_id); si alguien agrega una columna a una sola tabla, esa prueba se cae.
-- -----------------------------------------------------------------------------
create table if not exists public.protocol_catalog_rules (
  -- de 0076 (menos organization_id):
  id uuid primary key default gen_random_uuid(),
  category text not null,
  inventory_item_id uuid references public.inventory_items(id) on delete cascade,
  name text,
  dimension text not null default 'none',
  min_value numeric(10, 2),
  max_value numeric(10, 2),
  quantity_mode text not null default 'fixed',
  quantity_value numeric(10, 2) not null default 1,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- de 0077:
  exudate_levels jsonb not null default '[]'::jsonb,
  zone_groups jsonb not null default '[]'::jsonb,
  infection text not null default 'any',
  priority int not null default 0,
  -- de 15.1.a:
  context_kind text,
  context_value text,
  scale_label text,
  trigger_label text,
  brand text,
  alt_name text,
  alt_brand text,
  note_phrase text
);
create index if not exists idx_protocol_catalog_rules_cat
  on public.protocol_catalog_rules(category);

comment on table public.protocol_catalog_rules is
  'Catálogo Kura+ del protocolo (del SISTEMA, sin organization_id). Misma forma que '
  'protocol_product_rules salvo la pertenencia a un centro. Lectura/escritura SOLO con '
  'el derecho protocol:author (Kura+); el centro que paga el protocolo lo recibe RESUELTO '
  '(etapa 2), nunca lee esta tabla. Se siembra en la etapa 5.';

-- -----------------------------------------------------------------------------
-- 15.1.c — El candado. Derecho nuevo protocol:author sobre la maquinaria de
-- org_entitlements (kind='module', key='protocol:author', status='active'), como el
-- AND de módulos de 0115. NO se otorga a nadie aquí.
-- -----------------------------------------------------------------------------
-- Helper: ¿el centro en sesión tiene protocol:author vigente? SECURITY DEFINER para
-- leer org_entitlements sin depender de su RLS (mismo patrón que is_master/is_admin).
create or replace function public.current_org_has_protocol_author()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.org_entitlements e
    where e.organization_id = public.current_organization_id()
      and e.kind = 'module'
      and e.key = 'protocol:author'
      and e.status = 'active'
  );
$$;
comment on function public.current_org_has_protocol_author() is
  'true si el centro en sesión tiene el derecho protocol:author vigente (org_entitlements '
  'kind=module key=protocol:author status=active). Gobierna la RLS de protocol_catalog_rules.';

alter table public.protocol_catalog_rules enable row level security;

-- SELECT + INSERT/UPDATE/DELETE: SOLO protocol:author (o master, según el patrón de las
-- demás tablas). Ni el que pague el protocolo Kura+ lee aquí: recibe resuelto (etapa 2).
-- Una sola política `for all`: `using` filtra lectura/borrado/edición, `with check` el alta.
drop policy if exists protocol_catalog_rules_all on public.protocol_catalog_rules;
create policy protocol_catalog_rules_all on public.protocol_catalog_rules
  for all
  using (public.is_master() or public.current_org_has_protocol_author())
  with check (public.is_master() or public.current_org_has_protocol_author());

-- Auditoría, igual que protocol_product_rules (la fn solo usa id + to_jsonb, no org_id).
drop trigger if exists trg_audit_protocol_catalog_rules on public.protocol_catalog_rules;
create trigger trg_audit_protocol_catalog_rules
  after insert or update or delete on public.protocol_catalog_rules
  for each row execute function public.audit_trigger_fn();
