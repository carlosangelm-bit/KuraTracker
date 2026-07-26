-- =============================================================================
-- 0051_consultation_supply_usage.sql — Insumos usados en una consulta (Fase B)
-- =============================================================================
-- El profesional marca, en la consulta, los insumos UTILIZADOS. Cada uno tiene
-- dos banderas INDEPENDIENTES (punto clave del flujo comercial):
--   * charge   → si se cobra al paciente (se suma al total de la consulta).
--   * discount → si se descuenta del inventario.
-- Un mismo insumo (p.ej. Prontosan) puede usarse en varias consultas sin cobrar
-- ni descontar cada vez. El descuento real al inventario y el cobro se
-- materializan al registrar el pago (fases C/D). Premium se valida en la app.
-- =============================================================================

create table if not exists public.consultation_supply_usage (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  patient_id uuid references public.patients(id) on delete set null,
  inventory_item_id uuid references public.inventory_items(id) on delete set null,
  name text not null,                    -- snapshot del nombre del insumo
  quantity integer not null default 1,
  charge boolean not null default true,      -- ¿se cobra al paciente?
  discount boolean not null default true,    -- ¿se descuenta del inventario?
  unit_cost numeric(10, 2),
  currency text default 'MXN',
  discounted boolean not null default false, -- ya se materializó la salida de inventario
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_consultation_supply_usage_consult
  on public.consultation_supply_usage(consultation_id);
create index if not exists idx_consultation_supply_usage_patient
  on public.consultation_supply_usage(patient_id);

alter table public.consultation_supply_usage enable row level security;

drop policy if exists consultation_supply_usage_select on public.consultation_supply_usage;
create policy consultation_supply_usage_select on public.consultation_supply_usage
  for select using (
    public.is_master() or organization_id = public.current_organization_id()
  );

drop policy if exists consultation_supply_usage_write on public.consultation_supply_usage;
create policy consultation_supply_usage_write on public.consultation_supply_usage
  for all using (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  ) with check (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );

drop trigger if exists trg_audit_consultation_supply_usage on public.consultation_supply_usage;
create trigger trg_audit_consultation_supply_usage
  after insert or update or delete on public.consultation_supply_usage
  for each row execute function public.audit_trigger_fn();

comment on table public.consultation_supply_usage is
  'Insumos utilizados en una consulta con banderas independientes charge '
  '(cobrar) y discount (descontar de inventario). Módulo Insumos, Fase B.';
