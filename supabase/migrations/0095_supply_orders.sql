-- =============================================================================
-- 0095_supply_orders.sql — Pedidos de insumos (cerrar el circuito de compra)
-- =============================================================================
-- Cuando un centro compra a Kura+ es un mismo movimiento físico que hoy queda
-- como dos eventos desconectados (venta en Shopify → ajuste en Kura+; y la
-- recepción "de la nada" en el centro). Falta la entidad de PEDIDO: qué se pidió
-- y contra qué cierra la recepción.
--
-- Alcance ACOTADO (no es un módulo de compras): pedido → recibido (total o
-- parcial). Sin aprobación, sin proveedores como entidad, sin estados complejos.
--
-- GOBERNANZA (crítico): el pedido pertenece al CENTRO QUE COMPRA. NO se modela
-- como una relación entre dos organizaciones. La visibilidad de la demanda de un
-- centro cliente desde Kura+ es una decisión de Carlos/contrato, no una función.
-- =============================================================================

create table if not exists public.supply_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  site_id uuid references public.sites(id) on delete set null,
  -- pendiente | parcial | recibido | cancelado
  status text not null default 'pendiente',
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.supply_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.supply_orders(id) on delete cascade,
  -- Denormalizado para una RLS uniforme (igual que charge_items).
  organization_id uuid not null references public.organizations(id) on delete cascade,
  inventory_item_id uuid references public.inventory_items(id) on delete set null,
  name text not null, -- snapshot del nombre pedido
  quantity_ordered integer not null,
  quantity_received integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_supply_orders_org on public.supply_orders(organization_id);
create index if not exists idx_supply_order_items_order on public.supply_order_items(order_id);

alter table public.supply_orders enable row level security;
alter table public.supply_order_items enable row level security;

-- RLS: master, o staff/admin del propio centro (mismo patrón que inventario).
create policy supply_orders_select on public.supply_orders for select using (
  public.is_master() or organization_id = public.current_organization_id()
);
create policy supply_orders_write on public.supply_orders for all using (
  public.is_master()
  or (organization_id = public.current_organization_id()
      and (public.is_admin() or public.current_staff_id() is not null))
) with check (
  public.is_master()
  or (organization_id = public.current_organization_id()
      and (public.is_admin() or public.current_staff_id() is not null))
);

create policy supply_order_items_select on public.supply_order_items for select using (
  public.is_master() or organization_id = public.current_organization_id()
);
create policy supply_order_items_write on public.supply_order_items for all using (
  public.is_master()
  or (organization_id = public.current_organization_id()
      and (public.is_admin() or public.current_staff_id() is not null))
) with check (
  public.is_master()
  or (organization_id = public.current_organization_id()
      and (public.is_admin() or public.current_staff_id() is not null))
);
