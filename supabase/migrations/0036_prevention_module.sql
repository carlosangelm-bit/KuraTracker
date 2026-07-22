-- 0036_prevention_module.sql
--
-- Módulo de PREVENCIÓN / RIESGO. Capa de apoyo a la decisión (DOCUMENTAL: no
-- toca el motor de tratamiento ni el arquetipo Kura+). Levanta alertas
-- preventivas según las características/comorbilidades del paciente en dos
-- frentes: riesgo de DESARROLLAR una lesión (LPP) y riesgo de COMPLICACIÓN en
-- una lesión existente. Las alertas se computan al vuelo en la app a partir de
-- estas tablas + comorbilidades + heridas (ver prevention_risk_engine.dart);
-- aquí solo se persisten los INSUMOS: internamiento y valoración de riesgo.
--
-- Dos tablas, mismo patrón multi-centro que 0025_adverse_events.sql
-- (RLS: master / admin de la org / clínico asignado; auditoría con
-- audit_trigger_fn).

-- -----------------------------------------------------------------------------
-- 1. Tipos
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'admission_status') then
    create type public.admission_status as enum ('activo', 'egresado');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 2. patient_admissions (internamiento episódico)
-- -----------------------------------------------------------------------------
create table if not exists public.patient_admissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  patient_id uuid not null references public.patients(id) on delete cascade,
  unit text,                    -- unidad / servicio (p.ej. "Medicina Interna")
  bed text,                     -- cama
  admitted_at timestamptz not null default now(),
  discharged_at timestamptz,    -- NULL = internamiento activo
  status public.admission_status not null default 'activo',
  notes text,
  created_at timestamptz not null default now()
);

comment on table public.patient_admissions is
  'Internamiento hospitalario del paciente (unidad/cama/ingreso). Episódico: '
  'una fila por internamiento; discharged_at NULL / status=activo = en curso. '
  'Alimenta el agrupado por unidad del tablero de riesgo.';

create index if not exists idx_patient_admissions_organization_id
  on public.patient_admissions(organization_id);
create index if not exists idx_patient_admissions_patient_id
  on public.patient_admissions(patient_id);
-- Un solo internamiento ACTIVO por paciente.
create unique index if not exists uq_patient_admissions_active
  on public.patient_admissions(patient_id)
  where status = 'activo';

-- -----------------------------------------------------------------------------
-- 3. risk_assessments (valoración de riesgo, independiente de herida)
-- -----------------------------------------------------------------------------
create table if not exists public.risk_assessments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  patient_id uuid not null references public.patients(id) on delete cascade,
  -- Escala de Braden (6-23): riesgo de lesión por presión. Independiente de una
  -- herida concreta, para poder prevenir en pacientes aún sin lesión.
  braden_score int check (braden_score is null or braden_score between 6 and 23),
  -- Subescalas opcionales (percepción sensorial, humedad, actividad, movilidad,
  -- nutrición, fricción/cizallamiento) como objeto JSON.
  braden_subscores jsonb,
  assessed_at timestamptz not null default now(),
  assessed_by uuid references public.staff(id),
  notes text,
  created_at timestamptz not null default now()
);

comment on table public.risk_assessments is
  'Valoración de riesgo (Braden) independiente de herida. Append-only; la más '
  'reciente alimenta el motor de prevención (prevention_risk_engine.dart).';

create index if not exists idx_risk_assessments_organization_id
  on public.risk_assessments(organization_id);
create index if not exists idx_risk_assessments_patient_id
  on public.risk_assessments(patient_id);
create index if not exists idx_risk_assessments_assessed_at
  on public.risk_assessments(assessed_at);

-- -----------------------------------------------------------------------------
-- 4. RLS (mismo patrón que adverse_events, 0025) — aplicado a ambas tablas
-- -----------------------------------------------------------------------------
alter table public.patient_admissions enable row level security;
alter table public.risk_assessments   enable row level security;

-- patient_admissions
drop policy if exists patient_admissions_select on public.patient_admissions;
create policy patient_admissions_select on public.patient_admissions
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patient_admissions.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );
drop policy if exists patient_admissions_insert on public.patient_admissions;
create policy patient_admissions_insert on public.patient_admissions
  for insert with check (
    organization_id = public.current_organization_id()
    and (
      public.is_admin()
      or exists (
        select 1 from public.staff_patient_assignments spa
        where spa.patient_id = patient_admissions.patient_id
          and spa.staff_id = public.current_staff_id()
      )
    )
  );
drop policy if exists patient_admissions_update on public.patient_admissions;
create policy patient_admissions_update on public.patient_admissions
  for update using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patient_admissions.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  ) with check (organization_id = public.current_organization_id());
drop policy if exists patient_admissions_admin_delete on public.patient_admissions;
create policy patient_admissions_admin_delete on public.patient_admissions
  for delete using (
    public.is_admin() and organization_id = public.current_organization_id()
  );

-- risk_assessments
drop policy if exists risk_assessments_select on public.risk_assessments;
create policy risk_assessments_select on public.risk_assessments
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = risk_assessments.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );
drop policy if exists risk_assessments_insert on public.risk_assessments;
create policy risk_assessments_insert on public.risk_assessments
  for insert with check (
    organization_id = public.current_organization_id()
    and (
      public.is_admin()
      or exists (
        select 1 from public.staff_patient_assignments spa
        where spa.patient_id = risk_assessments.patient_id
          and spa.staff_id = public.current_staff_id()
      )
    )
  );
drop policy if exists risk_assessments_update on public.risk_assessments;
create policy risk_assessments_update on public.risk_assessments
  for update using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = risk_assessments.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  ) with check (organization_id = public.current_organization_id());
drop policy if exists risk_assessments_admin_delete on public.risk_assessments;
create policy risk_assessments_admin_delete on public.risk_assessments
  for delete using (
    public.is_admin() and organization_id = public.current_organization_id()
  );

-- -----------------------------------------------------------------------------
-- 5. Auditoría (dato clínico, mismo patrón que 0002/0025)
-- -----------------------------------------------------------------------------
drop trigger if exists trg_audit_patient_admissions on public.patient_admissions;
create trigger trg_audit_patient_admissions
  after insert or update or delete on public.patient_admissions
  for each row execute function public.audit_trigger_fn();

drop trigger if exists trg_audit_risk_assessments on public.risk_assessments;
create trigger trg_audit_risk_assessments
  after insert or update or delete on public.risk_assessments
  for each row execute function public.audit_trigger_fn();
