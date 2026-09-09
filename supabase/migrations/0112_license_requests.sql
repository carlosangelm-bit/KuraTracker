-- =============================================================================
-- 0112_license_requests.sql — Solicitudes de más licencias (compra por solicitud).
-- =============================================================================
-- INTERINO: hasta que exista la pila de suscripciones de Stripe (customer,
-- tarjeta guardada, subscription items, prorrateo, eventos de suscripción en el
-- webhook — fases 3-5), el panel de licencias del admin NO cobra dentro de la app.
-- Todo aumento de licencias entra por aquí: una fila que la plataforma (Cowork)
-- atiende. Es el canal AUDITABLE del embudo (incluye el momento del techo de
-- autoservicio, donde el centro pide pagar más).
--
-- El derecho lo sigue escribiendo ÚNICAMENTE el webhook/master (org_entitlements,
-- 0108): esta tabla es una SOLICITUD, no un derecho. No enciende nada por sí sola.
-- =============================================================================

create table if not exists public.license_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  -- Qué pide el centro más: asientos clínicos, licencias de Protocolo Kura+, un
  -- módulo (insumos/comercial/admin), o texto libre.
  kind text not null check (kind in ('seat_clinico', 'protocolo', 'module', 'otro')),
  -- Cuántas más (para seat_clinico/protocolo); null en module/otro.
  requested_quantity integer check (requested_quantity is null or requested_quantity > 0),
  -- Para kind='module', qué módulo; para 'otro', el detalle libre.
  detail text,
  note text,

  status text not null default 'open' check (status in ('open', 'handled', 'cancelled')),

  created_by uuid references public.profiles(id),
  created_by_role text,
  created_at timestamptz not null default now(),
  handled_at timestamptz,
  handled_by uuid references public.profiles(id)
);

comment on table public.license_requests is
  'Solicitudes de más licencias del admin del centro (compra por solicitud, interino '
  'hasta la pila de suscripciones de Stripe). Es una SOLICITUD, no un derecho: no '
  'enciende nada; el derecho lo escribe el webhook/master en org_entitlements.';

create index if not exists idx_license_requests_org on public.license_requests(organization_id);
create index if not exists idx_license_requests_status on public.license_requests(status);

alter table public.license_requests enable row level security;

-- SELECT: master (Cowork, ve todas) o el admin del centro (ve las suyas).
create policy license_requests_select on public.license_requests
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

-- INSERT: el admin del centro (o master), solo para su propio centro.
create policy license_requests_insert on public.license_requests
  for insert with check (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );

-- UPDATE/DELETE: solo master (Cowork atiende/cierra la solicitud).
create policy license_requests_update on public.license_requests
  for update using (public.is_master()) with check (public.is_master());
create policy license_requests_delete on public.license_requests
  for delete using (public.is_master());
