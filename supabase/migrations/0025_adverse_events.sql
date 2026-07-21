-- 0025_adverse_events.sql
--
-- Módulo de EVENTOS ADVERSOS (Protocolo "Manejo de eventos adversos",
-- vigilancia COFEPRIS). Registra los eventos adversos ocurridos durante el
-- seguimiento de una herida, ligados al paciente y (opcionalmente) a la
-- herida/consulta donde se detectaron, con su clasificación por gravedad,
-- las señales de alarma observadas, las acciones tomadas y la evolución.
--
-- Regla de negocio (aplicada en la app, ver AdverseEvent en Dart): un evento
-- de gravedad "centinela" exige reporte a la autoridad en <=24 h. El campo
-- reported_at registra CUÁNDO se reportó (NULL = aún sin reportar); la UI
-- calcula el vencimiento (occurred_at + 24 h) y muestra la marca de alerta y
-- el recordatorio mientras reported_at siga NULL.
--
-- RLS: mismo patrón multi-centro del resto del esquema
-- (is_master / is_admin + current_organization_id / current_staff_id, ver
-- 0003/0011/0012). Un admin ve/gestiona los eventos de SU organización; un
-- clínico, los de sus pacientes asignados (staff_patient_assignments) o los
-- que él mismo registró.

-- -----------------------------------------------------------------------------
-- 1. Tipo de gravedad
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'adverse_event_severity') then
    create type public.adverse_event_severity as enum
      ('leve', 'moderado', 'grave', 'centinela');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 2. Tabla adverse_events
-- -----------------------------------------------------------------------------
create table if not exists public.adverse_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  patient_id uuid not null references public.patients(id) on delete cascade,
  -- Herida/consulta donde se detectó el evento (opcionales: un evento puede
  -- no estar ligado a una herida concreta ni a una consulta registrada).
  wound_id uuid references public.wounds(id) on delete set null,
  consultation_id uuid references public.consultations(id) on delete set null,
  -- Personal que registra/reporta el evento. Nullable: un admin de licencia
  -- individual puede no tener fila propia en staff (ver 0011).
  staff_id uuid references public.staff(id),
  occurred_at timestamptz not null,
  -- Tipo de evento adverso (texto controlado en la app, catálogo del
  -- protocolo: infección, dehiscencia, reacción a material, caída, etc.).
  type text not null,
  severity public.adverse_event_severity not null,
  -- Checklist de señales de alarma como objeto JSON booleano, p.ej.
  -- {"fiebre_38": true, "sangrado_10min": false, "linfangitis": true,
  --  "signos_sistemicos": false}. Extensible sin migración.
  alarm_signs jsonb not null default '{}'::jsonb,
  description text,
  actions_taken text,
  evolution text,
  -- Momento en que se reportó a la autoridad (COFEPRIS). NULL = pendiente.
  reported_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.adverse_events is
  'Eventos adversos (Protocolo "Manejo de eventos adversos" / vigilancia '
  'COFEPRIS). Ligados a paciente y opcionalmente a herida/consulta. '
  'severity=centinela exige reporte <=24 h (reported_at NULL = pendiente).';
comment on column public.adverse_events.alarm_signs is
  'Checklist de señales de alarma como JSON booleano (fiebre_38, '
  'sangrado_10min, linfangitis, signos_sistemicos, ...).';
comment on column public.adverse_events.reported_at is
  'Fecha/hora de reporte a la autoridad. NULL = pendiente. Para eventos '
  'centinela el vencimiento es occurred_at + 24 h.';

create index if not exists idx_adverse_events_organization_id
  on public.adverse_events(organization_id);
create index if not exists idx_adverse_events_patient_id
  on public.adverse_events(patient_id);
create index if not exists idx_adverse_events_wound_id
  on public.adverse_events(wound_id);
create index if not exists idx_adverse_events_consultation_id
  on public.adverse_events(consultation_id);
create index if not exists idx_adverse_events_occurred_at
  on public.adverse_events(occurred_at);
-- Parcial: acelera "centinela pendiente de reporte" (marca de alerta ≤24 h).
create index if not exists idx_adverse_events_centinela_pendiente
  on public.adverse_events(occurred_at)
  where severity = 'centinela' and reported_at is null;

-- -----------------------------------------------------------------------------
-- 3. RLS
-- -----------------------------------------------------------------------------
alter table public.adverse_events enable row level security;

-- SELECT: master (plataforma); admin de la organización; el staff que lo
-- registró; o el clínico asignado al paciente.
drop policy if exists adverse_events_select on public.adverse_events;
create policy adverse_events_select on public.adverse_events
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or staff_id = public.current_staff_id()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = adverse_events.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- INSERT: dentro de la propia organización, por un admin de la organización o
-- un clínico asignado al paciente.
drop policy if exists adverse_events_insert on public.adverse_events;
create policy adverse_events_insert on public.adverse_events
  for insert with check (
    organization_id = public.current_organization_id()
    and (
      public.is_admin()
      or exists (
        select 1 from public.staff_patient_assignments spa
        where spa.patient_id = adverse_events.patient_id
          and spa.staff_id = public.current_staff_id()
      )
    )
  );

-- UPDATE: admin de la organización o clínico asignado (p.ej. registrar
-- reported_at o actualizar la evolución). Se conserva la organización.
drop policy if exists adverse_events_update on public.adverse_events;
create policy adverse_events_update on public.adverse_events
  for update using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = adverse_events.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  ) with check (
    organization_id = public.current_organization_id()
  );

-- DELETE: solo admin de la organización (registro regulatorio; el clínico no
-- borra eventos adversos).
drop policy if exists adverse_events_admin_delete on public.adverse_events;
create policy adverse_events_admin_delete on public.adverse_events
  for delete using (
    public.is_admin() and organization_id = public.current_organization_id()
  );

-- -----------------------------------------------------------------------------
-- 4. Auditoría (dato clínico/regulatorio sensible, mismo patrón que 0002)
-- -----------------------------------------------------------------------------
drop trigger if exists trg_audit_adverse_events on public.adverse_events;
create trigger trg_audit_adverse_events
  after insert or update or delete on public.adverse_events
  for each row execute function public.audit_trigger_fn();
