-- 0016_acuity_agenda.sql
--
-- Integración con Acuity Scheduling: agenda de citas visible/gestionable
-- desde KuraTracker.
--
-- Arquitectura (ver supabase/functions/README.md):
--   Flutter ──► Edge Function "acuity-proxy" ──► Acuity API      (lectura/escritura)
--   Acuity  ──► Edge Function "acuity-webhook" ─► esta tabla     (sincronización)
--
-- Las Edge Functions usan la SERVICE ROLE (bypass de RLS) para ESCRIBIR aquí.
-- El cliente (app) SOLO LEE esta tabla; crea/reagenda/cancela a través del
-- proxy (Acuity es la fuente de verdad, el webhook refleja el cambio aquí).
-- Por eso abajo solo hay policy de SELECT: INSERT/UPDATE/DELETE quedan sin
-- policy => denegados a cualquier cliente, permitidos solo a service_role.

-- 1) Mapeo Kurador -> calendario de Acuity. Permite resolver a qué staff (y
--    organización) pertenece cada cita según su calendarID de Acuity, y que
--    "cada profesional vea SU agenda".
alter table public.staff
  add column if not exists acuity_calendar_id bigint;

create index if not exists idx_staff_acuity_calendar_id
  on public.staff(acuity_calendar_id);

comment on column public.staff.acuity_calendar_id is
  'ID del calendario de Acuity Scheduling asociado a este Kurador. Lo usa la '
  'Edge Function acuity-webhook para resolver staff_id/organization_id de cada '
  'cita entrante. NULL = este personal no tiene agenda de Acuity vinculada.';

-- 2) Tabla de citas (espejo local de Acuity para lectura en tiempo real vía
--    Supabase Realtime).
create table if not exists public.appointments (
  -- id de la cita en Acuity (fuente de verdad).
  id bigint primary key,
  organization_id uuid references public.organizations(id),
  -- staff (Kurador) resuelto desde acuity_calendar_id. Puede quedar NULL si el
  -- calendario aún no está mapeado a ningún staff.
  staff_id uuid references public.staff(id),
  acuity_calendar_id bigint,
  appointment_type_id bigint,
  appointment_type text,
  first_name text,
  last_name text,
  email text,
  phone text,
  datetime timestamptz,
  end_time timestamptz,
  -- scheduled | rescheduled | canceled
  status text not null default 'scheduled',
  -- respuesta completa de Acuity, por si se necesita algún campo extra.
  raw jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists idx_appointments_organization_id
  on public.appointments(organization_id);
create index if not exists idx_appointments_staff_id
  on public.appointments(staff_id);
create index if not exists idx_appointments_datetime
  on public.appointments(datetime);

-- 3) RLS: mismo patrón que el resto del esquema multi-centro
--    (is_master / is_admin / current_organization_id / current_staff_id,
--    ver 0003/0011/0012).
alter table public.appointments enable row level security;

drop policy if exists appointments_select on public.appointments;
create policy appointments_select on public.appointments
  for select
  using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or (staff_id = public.current_staff_id())
  );

-- Sin policies de INSERT/UPDATE/DELETE a propósito: solo la service_role
-- (Edge Functions) escribe aquí. La app nunca escribe directo esta tabla.

comment on table public.appointments is
  'Espejo local de las citas de Acuity Scheduling. Lo escribe SOLO la Edge '
  'Function acuity-webhook (service role); la app lo lee vía RLS y crea/edita '
  'a través de la Edge Function acuity-proxy.';
