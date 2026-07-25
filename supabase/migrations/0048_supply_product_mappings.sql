-- =============================================================================
-- 0048_supply_product_mappings.sql — Mapeo insumo del protocolo ↔ producto tienda
-- =============================================================================
-- Módulo de Insumos, Fase 2 (premium): cada centro liga un insumo GENÉRICO de su
-- protocolo (par método + producto genérico, p.ej. Apósito / "Espuma con borde
-- adhesivo") a un PRODUCTO concreto de su tienda Shopify (p.ej. "Mepilex Border").
-- Es la base para asignar insumos a pacientes, costear y sugerir reabasto.
-- Se guarda una foto (título/imagen/precio) del producto para mostrar sin llamar
-- a Shopify. La licencia premium se valida en la app (organizations.premium_insumos).
-- =============================================================================

create table if not exists public.supply_product_mappings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  method text not null,            -- método del protocolo (ej. 'Apósito')
  generic_product text not null,   -- insumo genérico (ej. 'Espuma con borde adhesivo')
  shopify_product_id text not null,        -- gid://shopify/Product/...
  shopify_variant_id text,                 -- variante específica (si aplica)
  shopify_title text not null,             -- foto: título del producto
  shopify_variant_title text,
  shopify_handle text,
  image_url text,
  price_amount numeric(10, 2),
  price_currency text,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (organization_id, method, generic_product)
);

create index if not exists idx_supply_product_mappings_org
  on public.supply_product_mappings(organization_id);

alter table public.supply_product_mappings enable row level security;

-- SELECT: cualquier miembro del centro (la fila es de su organización) o master.
drop policy if exists supply_product_mappings_select on public.supply_product_mappings;
create policy supply_product_mappings_select on public.supply_product_mappings
  for select using (
    public.is_master()
    or organization_id = public.current_organization_id()
  );

-- INSERT/UPDATE/DELETE: personal del centro (admin o clínico con ficha staff) de
-- la propia organización, o master. (La licencia premium se aplica en la app.)
drop policy if exists supply_product_mappings_insert on public.supply_product_mappings;
create policy supply_product_mappings_insert on public.supply_product_mappings
  for insert with check (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );

drop policy if exists supply_product_mappings_update on public.supply_product_mappings;
create policy supply_product_mappings_update on public.supply_product_mappings
  for update using (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );

drop policy if exists supply_product_mappings_delete on public.supply_product_mappings;
create policy supply_product_mappings_delete on public.supply_product_mappings
  for delete using (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );

drop trigger if exists trg_audit_supply_product_mappings on public.supply_product_mappings;
create trigger trg_audit_supply_product_mappings
  after insert or update or delete on public.supply_product_mappings
  for each row execute function public.audit_trigger_fn();

comment on table public.supply_product_mappings is
  'Mapeo insumo del protocolo (método + producto genérico) ↔ producto de la tienda '
  'Shopify, por centro (módulo Insumos, Fase 2 premium).';
