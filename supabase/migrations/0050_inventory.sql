-- =============================================================================
-- 0050_inventory.sql — Inventario de insumos por sitio (Insumos, Fase 3 premium)
-- =============================================================================
-- El centro lleva existencias POR SITIO. Un artículo de inventario puede ser un
-- producto de la tienda Kura+ (con id/precio de Shopify) o un producto EXTERNO
-- que el centro compra en otro lado (captura manual: nombre, costo, proveedor).
-- La existencia actual = suma de los movimientos (entradas/salidas/ajustes); es
-- una BITÁCORA, no un contador editable directo. Premium se valida en la app.
-- =============================================================================

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  name text not null,
  is_external boolean not null default false,   -- true = producto fuera de Kura+
  shopify_product_id text,                       -- null para externos
  shopify_variant_id text,
  image_url text,
  unit_cost numeric(10, 2),                      -- costo unitario (snapshot/editable)
  currency text default 'MXN',
  supplier text,                                 -- proveedor (externos)
  reorder_threshold integer,                     -- umbral de reorden (Fase 5)
  notes text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_inventory_items_site
  on public.inventory_items(site_id);
create index if not exists idx_inventory_items_org
  on public.inventory_items(organization_id);

-- Evita duplicar el MISMO producto de tienda en un sitio (los externos sí pueden
-- repetir nombre). coalesce('') para tratar variante nula de forma estable.
create unique index if not exists uq_inventory_items_site_product
  on public.inventory_items(site_id, shopify_product_id, coalesce(shopify_variant_id, ''))
  where shopify_product_id is not null and not is_external;

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  delta integer not null,          -- + entrada, - salida
  reason text not null,            -- compra | consumo | ajuste | merma | conteo | devolucion
  unit_cost numeric(10, 2),        -- costo del movimiento (entradas)
  patient_id uuid references public.patients(id) on delete set null,   -- consumo (Fase 4)
  consultation_id uuid references public.consultations(id) on delete set null,
  note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_inventory_movements_item
  on public.inventory_movements(inventory_item_id);
create index if not exists idx_inventory_movements_site
  on public.inventory_movements(site_id);

alter table public.inventory_items enable row level security;
alter table public.inventory_movements enable row level security;

-- SELECT: miembros del centro (fila de su organización) o master.
-- WRITE: staff/admin del centro o master. (Premium se aplica en la app.)
do $$
declare
  t text;
begin
  foreach t in array array['inventory_items', 'inventory_movements'] loop
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

comment on table public.inventory_items is
  'Artículos de inventario por sitio (producto de la tienda Kura+ o externo). '
  'Existencia = suma de inventory_movements. Módulo Insumos, Fase 3 premium.';
comment on table public.inventory_movements is
  'Bitácora de movimientos de inventario (entrada/salida/ajuste). La existencia '
  'de un artículo es la suma de sus delta.';
