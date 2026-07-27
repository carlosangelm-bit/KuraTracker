-- =============================================================================
-- 0055_point_payments.sql — Cobros con Mercado Pago Point + conciliación
-- =============================================================================
-- Prepara la conciliación de pagos con terminal Mercado Pago Point (modo
-- integrado). Aditivo:
--  1) charges gana campos de referencia externa / proveedor para ligar el pago
--     de la terminal al cobro (external_reference = consulta/folio del paciente).
--  2) point_payments = BANDEJA de conciliación: cada pago entrante de la terminal
--     (vía webhook en Fase 2, o registrado a mano en Fase 1) llega aquí y se liga
--     a su charge. Los que no calzan quedan sin ligar (charge_id null) para que
--     atención a clientes los concilie.
-- Premium se valida en la app (organizations.premium_insumos), igual que 0052.
-- =============================================================================

-- 1) Campos de pago externo en charges (idempotente) ------------------------
alter table public.charges
  add column if not exists payment_provider text;   -- 'manual' | 'mercadopago'
alter table public.charges
  add column if not exists external_reference text;  -- ref enviada a la terminal
alter table public.charges
  add column if not exists mp_payment_id text;       -- id del pago en Mercado Pago
alter table public.charges
  add column if not exists mp_status text;           -- estado del pago en MP

create index if not exists idx_charges_external_ref
  on public.charges(external_reference);
create index if not exists idx_charges_mp_payment
  on public.charges(mp_payment_id);

-- 2) Bandeja de conciliación -------------------------------------------------
create table if not exists public.point_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  mp_payment_id text,                 -- id del pago en Mercado Pago (si aplica)
  amount numeric(10, 2) not null default 0,
  currency text default 'MXN',
  status text not null default 'approved',  -- approved | rejected | refunded | pending
  method text,                        -- credit_card | debit_card | ...
  external_reference text,            -- ref enviada al crear el cobro (consulta/folio)
  device_id text,                     -- terminal Point
  description text,
  captured_at timestamptz,            -- cuándo se cobró en la terminal
  charge_id uuid references public.charges(id) on delete set null, -- null = sin ligar
  linked_by uuid references public.profiles(id),
  linked_at timestamptz,
  raw jsonb,                          -- payload crudo de Mercado Pago (auditoría)
  source text not null default 'manual',   -- manual | webhook
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_point_payments_org on public.point_payments(organization_id);
create index if not exists idx_point_payments_charge on public.point_payments(charge_id);
create index if not exists idx_point_payments_extref on public.point_payments(external_reference);
create index if not exists idx_point_payments_mp on public.point_payments(mp_payment_id);

alter table public.point_payments enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['point_payments'] loop
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

comment on table public.point_payments is
  'Bandeja de conciliación de pagos con Mercado Pago Point. charge_id null = sin ligar.';
