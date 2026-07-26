-- =============================================================================
-- 0052_commercial.sql — Módulo comercial: catálogo de servicios + cobros (Fase C)
-- =============================================================================
-- Cada centro define un CATÁLOGO DE SERVICIOS con su honorario (Valoración,
-- Seguimiento, Curación…). Al cobrar una consulta se crea un COBRO (charge) =
-- honorario del servicio + insumos marcados "cobrar" (0051). El cobro se paga
-- (por ahora manual: efectivo/transferencia/tarjeta; Stripe en la Fase D) y al
-- pagarse se materializa el descuento de inventario de los insumos "descontar".
-- charge_items guarda el desglose (para historial y futura facturación).
-- Premium se valida en la app (organizations.premium_insumos).
-- =============================================================================

create table if not exists public.service_catalog (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  price numeric(10, 2) not null default 0,
  currency text default 'MXN',
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_service_catalog_org on public.service_catalog(organization_id);

create table if not exists public.charges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  patient_id uuid references public.patients(id) on delete set null,
  consultation_id uuid references public.consultations(id) on delete set null,
  site_id uuid references public.sites(id) on delete set null,
  subtotal_service numeric(10, 2) not null default 0,
  subtotal_supplies numeric(10, 2) not null default 0,
  total numeric(10, 2) not null default 0,
  currency text default 'MXN',
  status text not null default 'pendiente',     -- pendiente | pagado | cancelado
  payment_method text,                          -- efectivo | transferencia | tarjeta | stripe | otro
  paid_at timestamptz,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_charges_org on public.charges(organization_id);
create index if not exists idx_charges_patient on public.charges(patient_id);
create index if not exists idx_charges_consult on public.charges(consultation_id);

create table if not exists public.charge_items (
  id uuid primary key default gen_random_uuid(),
  charge_id uuid not null references public.charges(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  kind text not null,                -- servicio | insumo
  name text not null,
  quantity integer not null default 1,
  unit_price numeric(10, 2) not null default 0,
  line_total numeric(10, 2) not null default 0,
  usage_id uuid references public.consultation_supply_usage(id) on delete set null,
  inventory_item_id uuid references public.inventory_items(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_charge_items_charge on public.charge_items(charge_id);

alter table public.service_catalog enable row level security;
alter table public.charges enable row level security;
alter table public.charge_items enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['service_catalog', 'charges', 'charge_items'] loop
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

comment on table public.service_catalog is 'Catálogo de servicios/honorarios por centro (módulo comercial, Fase C).';
comment on table public.charges is 'Cobro de una consulta (honorario + insumos). Módulo comercial.';
comment on table public.charge_items is 'Desglose de un cobro (servicio/insumo) para historial y facturación.';
