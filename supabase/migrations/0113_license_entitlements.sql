-- =============================================================================
-- 0113_license_entitlements.sql — Modelo de licencia en la base (Fase 1, §3).
-- =============================================================================
-- Separa LO QUE EL CENTRO PAGÓ (derechos) de LO QUE EL CENTRO DECIDE MOSTRAR
-- (module_settings). Hoy no hay ninguna relación entre módulos y pago: el admin
-- de un centro puede encender Insumos o Comercial sin haberlos comprado
-- (module_settings_insert del 0041 permite escribir al admin de la org) y queda
-- encendido de verdad. Esta migración crea la capa de DERECHOS; el AND efectivo
-- en la app (§4) y el candado en module_settings (§5) llegan después.
--
-- INERTE por sí sola: solo agrega tablas y RLS, no cambia comportamiento. El
-- backfill (0114) y el candado (0115) son los que mueven el comportamiento.
--
-- Numeración: la fase 1 se renumeró de 0108-0112 a 0113-0117 al rebasar sobre
-- staging, que ya ocupa 0108-0112 (motor de visión 0108-0110 + guardas de rol
-- 0111-0112). El sandbox aplica estas 0113+ ENCIMA de lo que ya tiene, sin reset.
-- El merge a main (que NO lleva el motor de visión) tomará estas migraciones de
-- licencia; los huecos 0108-0110 quedan reservados para visión si algún día entra.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 3.1 org_entitlements — lo que el centro pagó. Una fila por concepto vigente.
-- -----------------------------------------------------------------------------
create table if not exists public.org_entitlements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  -- Qué clase de derecho: plan (nivel del centro), módulo, o asiento.
  kind text not null check (kind in ('plan', 'module', 'seat')),
  -- Identificador dentro de la clase:
  --   plan   → 'gratuito' | 'basico'
  --   module → 'clinico' | 'insumos' | 'comercial' | 'admin'
  --   seat   → 'clinico' | 'protocolo'
  key text not null,

  -- Cantidad SOLO para kind='seat' (número de asientos/cupos); null en los demás.
  quantity integer,
  constraint ent_quantity_shape check (
    (kind = 'seat' and quantity is not null and quantity >= 0)
    or (kind <> 'seat' and quantity is null)
  ),

  status text not null default 'active' check (status in ('active', 'past_due', 'canceled')),
  current_period_end timestamptz,

  -- Enlace a Stripe cuando el derecho vino de una suscripción; null cuando lo
  -- otorgó el master a mano.
  stripe_subscription_item_id text,
  -- Quién escribió el derecho. 'stripe' = webhook (service_role); 'master' = a
  -- mano desde Plataforma o el backfill.
  source text not null check (source in ('stripe', 'master')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Un solo derecho vigente por (centro, clase, key). El webhook hace upsert sobre
-- esta unicidad; el backfill también.
create unique index if not exists uq_org_entitlements_org_kind_key
  on public.org_entitlements(organization_id, kind, key);
create index if not exists idx_org_entitlements_org on public.org_entitlements(organization_id);

comment on table public.org_entitlements is
  'Derechos vigentes de un centro (lo que PAGÓ), separado de module_settings (lo '
  'que MUESTRA). Escritura solo master (o service_role del webhook, que salta RLS); '
  'el admin del centro NO tiene policy de escritura aquí a propósito: es lo que '
  'cierra el hueco de encender módulos sin pagarlos.';
comment on column public.org_entitlements.quantity is
  'Asientos/cupos, solo para kind=seat. null en plan/module.';
comment on column public.org_entitlements.source is
  'stripe = lo escribió el webhook (service_role); master = otorgado a mano/backfill.';

alter table public.org_entitlements enable row level security;

-- SELECT: miembros del centro (para que la app compute el AND) y master.
create policy org_entitlements_select on public.org_entitlements
  for select using (
    organization_id = public.current_organization_id()
    or public.is_master()
  );

-- INSERT/UPDATE/DELETE: SOLO master. NO hay policy para el admin de la org —
-- ese es el punto central de la fase. El webhook escribe con service_role, que
-- salta RLS por definición, así que no necesita policy.
create policy org_entitlements_insert on public.org_entitlements
  for insert with check (public.is_master());
create policy org_entitlements_update on public.org_entitlements
  for update using (public.is_master()) with check (public.is_master());
create policy org_entitlements_delete on public.org_entitlements
  for delete using (public.is_master());

-- -----------------------------------------------------------------------------
-- 3.2 billing_catalog — traducción de un price de Stripe a un concepto. Así el
--     webhook traduce sin IDs a mano y el sitio lee precios de una sola fuente.
-- -----------------------------------------------------------------------------
-- Identidad = lookup_key de Stripe (idéntica en prueba y producción; se puede
-- MOVER a un price nuevo con transfer_lookup_key sin tocar la base — una
-- suscripción vieja apuntando al price viejo sigue mapeando al mismo concepto,
-- que es lo que se quiere: el derecho es el mismo, solo cambió el monto). El
-- price_id, en cambio, difiere por entorno; queda como columna informativa.
create table if not exists public.billing_catalog (
  lookup_key text primary key,
  kind text not null check (kind in ('plan', 'module', 'seat')),
  key text not null,
  interval text not null check (interval in ('month', 'year')),
  unit text not null check (unit in ('seat', 'center')),
  stripe_price_id text,          -- informativo, por entorno; puede ser null
  created_at timestamptz not null default now()
);

comment on table public.billing_catalog is
  'Traducción lookup_key de Stripe → (kind, key, interval, unit). Fuente única '
  'para que el webhook mapee sin IDs a mano y el checkout resuelva precios por '
  'clave. La clave es idéntica en prueba/prod; stripe_price_id es informativo por '
  'entorno. SELECT abierto a authenticated; escritura solo master.';

alter table public.billing_catalog enable row level security;

-- SELECT abierto a authenticated (el sitio muestra precios).
create policy billing_catalog_select on public.billing_catalog
  for select using (true);
-- Escritura solo master.
create policy billing_catalog_insert on public.billing_catalog
  for insert with check (public.is_master());
create policy billing_catalog_update on public.billing_catalog
  for update using (public.is_master()) with check (public.is_master());
create policy billing_catalog_delete on public.billing_catalog
  for delete using (public.is_master());

-- -----------------------------------------------------------------------------
-- 3.3 stripe_events — idempotencia. El webhook inserta ANTES de procesar; si el
--     insert choca contra la PK, el evento ya se procesó y responde 200 sin
--     repetir. Con suscripciones, el reenvío de Stripe es rutina, no excepción.
-- -----------------------------------------------------------------------------
create table if not exists public.stripe_events (
  event_id text primary key,
  type text not null,
  received_at timestamptz not null default now()
);

comment on table public.stripe_events is
  'Registro de eventos de Stripe ya vistos, para idempotencia del webhook. Lo '
  'escribe el webhook con service_role (salta RLS). RLS habilitada SIN policies: '
  'ningún cliente authenticated puede leer ni escribir; solo service_role.';

-- RLS habilitada y SIN policies: solo service_role (que salta RLS) la toca.
alter table public.stripe_events enable row level security;
