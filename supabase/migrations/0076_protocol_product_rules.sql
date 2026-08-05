-- =============================================================================
-- 0076_protocol_product_rules.sql — Vínculo protocolo → producto por MEDIDA
-- =============================================================================
-- Cierra el eslabón que faltaba: el régimen del motor sale como (método →
-- producto genérico en prosa) y hoy no aterriza en productos concretos. Aquí el
-- centro configura, POR CATEGORÍA del protocolo (KuraTag: limpieza,
-- desbridamiento, aposito, relleno_cavidad, proteccion_piel, antimicrobiano,
-- compresion, descarga), REGLAS que resuelven el producto concreto y su cantidad
-- SEGÚN LA MEDIDA de la herida:
--   - dimension 'none'   → aplica siempre (producto fijo).
--   - dimension 'area'   → aplica si area_cm2 ∈ [min,max)  (p. ej. tamaño de apósito).
--   - dimension 'volume' → aplica si volume_cm3 ∈ [min,max) (p. ej. relleno).
--   - cantidad: 'fixed' (p. ej. 1 apósito) | 'per_area' (× área) | 'per_volume'
--     (× volumen) — p. ej. ml de solución por cm².
--
-- El motor ya mapea método → KuraTag; la resolución (app) usa esta tabla en
-- TODOS los flujos (armador del plan, "sugerir del plan" del seguimiento).
--
-- RLS ADITIVA, patrón point_payments/patient_labs. Permite productos NO-Shopify
-- (referencia directa a inventory_items, no por shopify_product_id).
-- =============================================================================

create table if not exists public.protocol_product_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category text not null,                 -- KuraTag.dbValue (aposito, relleno_cavidad, ...)
  inventory_item_id uuid references public.inventory_items(id) on delete cascade,
  name text,                              -- nombre del producto (denormalizado, historial)
  dimension text not null default 'none', -- none | area | volume
  min_value numeric(10, 2),               -- límite inferior de la medida (null = -inf)
  max_value numeric(10, 2),               -- límite superior, exclusivo (null = +inf)
  quantity_mode text not null default 'fixed', -- fixed | per_area | per_volume
  quantity_value numeric(10, 2) not null default 1, -- fija, o factor por cm²/cm³
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_protocol_product_rules_org
  on public.protocol_product_rules(organization_id);
create index if not exists idx_protocol_product_rules_cat
  on public.protocol_product_rules(organization_id, category);

do $$
declare
  t text;
begin
  foreach t in array array['protocol_product_rules'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %1$s_select on public.%1$s', t);
    execute format($p$
      create policy %1$s_select on public.%1$s for select using (
        public.is_master() or organization_id = public.current_organization_id()
      )$p$, t);
    execute format('drop policy if exists %1$s_write on public.%1$s', t);
    execute format($p$
      create policy %1$s_write on public.%1$s for all using (
        public.is_master()
        or (organization_id = public.current_organization_id()
            and (public.is_admin() or public.current_staff_id() is not null))
      ) with check (
        public.is_master()
        or (organization_id = public.current_organization_id()
            and (public.is_admin() or public.current_staff_id() is not null))
      )$p$, t);
    execute format('drop trigger if exists trg_audit_%1$s on public.%1$s', t);
    execute format($p$
      create trigger trg_audit_%1$s after insert or update or delete on public.%1$s
      for each row execute function public.audit_trigger_fn()$p$, t);
  end loop;
end $$;

comment on table public.protocol_product_rules is
  'Reglas producto-por-categoría del protocolo, con selección por MEDIDA de la herida (área/volumen). Cierra el vínculo protocolo→producto en todos los flujos de consulta.';
