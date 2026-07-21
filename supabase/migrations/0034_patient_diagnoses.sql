-- 0034_patient_diagnoses.sql
--
-- Diagnósticos CIE-10 del expediente (NOM-004: codificación diagnóstica
-- estandarizada). Cada diagnóstico asignado a un paciente referencia un código
-- del catálogo reducido de heridas crónicas (que vive como ASSET empaquetado,
-- no en la BD: assets/data/cie10_heridas.json, ver lib/engine/cie10_catalog.dart),
-- y guarda su relación con la herida (causa/comorbilidad/consecuencia/herida),
-- si es el diagnóstico principal, su estado (activo/resuelto/descartado) y, de
-- forma opcional, la herida concreta a la que aplica.
--
-- Alcance DOCUMENTAL: estos diagnósticos NO alimentan el motor Kura+ ni las
-- comorbilidades del arquetipo (esas siguen en patient_comorbidities). Son el
-- registro diagnóstico del expediente para cumplimiento y reportes.
--
-- Inmutabilidad regulatoria: se guarda un SNAPSHOT del nombre (`name`) además
-- del código, para que el registro conserve la descripción vigente al momento
-- de capturarlo aunque el asset del catálogo cambie después.
--
-- Modelo append-only (igual que patient_comorbidities): una fila por
-- (patient_id, code); el ciclo de vida se maneja con `status` (no se borra:
-- un dx que deja de aplicar se marca "descartado"/"resuelto"). El historial de
-- cambios queda en audit_log (trigger).
--
-- RLS: mismo patrón multi-centro del resto del esquema (is_master / is_admin +
-- current_organization_id / current_staff_id + staff_patient_assignments),
-- copiado de 0025_adverse_events.sql.

-- -----------------------------------------------------------------------------
-- 1. Tipos
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'diagnosis_relation') then
    create type public.diagnosis_relation as enum
      ('causa', 'comorbilidad', 'consecuencia', 'herida');
  end if;
  if not exists (select 1 from pg_type where typname = 'diagnosis_status') then
    create type public.diagnosis_status as enum
      ('activo', 'resuelto', 'descartado');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 2. Tabla patient_diagnoses
-- -----------------------------------------------------------------------------
create table if not exists public.patient_diagnoses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  patient_id uuid not null references public.patients(id) on delete cascade,
  -- Herida concreta a la que aplica el dx (opcional; típico en relation='herida').
  wound_id uuid references public.wounds(id) on delete set null,
  -- Personal que registró/actualizó el dx. Nullable: un admin de licencia
  -- individual puede no tener fila propia en staff (ver 0011).
  staff_id uuid references public.staff(id),
  -- Código CIE-10 (CATALOG_KEY del asset) + SNAPSHOT del nombre vigente.
  code text not null,
  name text not null,
  relation public.diagnosis_relation not null,
  is_primary boolean not null default false,
  status public.diagnosis_status not null default 'activo',
  notes text,
  -- Atribución fecha + autor que exige la NOM-004 (igual que 0030).
  noted_at timestamptz not null default now(),
  noted_by uuid references public.staff(id),
  created_at timestamptz not null default now(),
  -- Un código por paciente: su ciclo de vida se maneja con `status`.
  unique (patient_id, code)
);

comment on table public.patient_diagnoses is
  'Diagnósticos CIE-10 del expediente (NOM-004). Referencian el catálogo '
  'reducido de heridas crónicas (asset, no BD). Alcance documental: NO '
  'alimentan el motor Kura+ (eso vive en patient_comorbidities).';
comment on column public.patient_diagnoses.name is
  'Snapshot de la descripción CIE-10 vigente al capturar el dx '
  '(inmutabilidad regulatoria aunque el asset del catálogo cambie).';
comment on column public.patient_diagnoses.relation is
  'Rol del dx frente a la herida: causa | comorbilidad | consecuencia | herida.';
comment on column public.patient_diagnoses.noted_by is
  'Profesional (staff) que registró/actualizó por última vez este dx. Junto '
  'con noted_at da la atribución fecha+autor que exige la NOM-004.';

create index if not exists idx_patient_diagnoses_organization_id
  on public.patient_diagnoses(organization_id);
create index if not exists idx_patient_diagnoses_patient_id
  on public.patient_diagnoses(patient_id);
create index if not exists idx_patient_diagnoses_wound_id
  on public.patient_diagnoses(wound_id);
-- Garantiza un solo diagnóstico principal por paciente.
create unique index if not exists uq_patient_diagnoses_primary
  on public.patient_diagnoses(patient_id)
  where is_primary;

-- -----------------------------------------------------------------------------
-- 3. RLS (mismo patrón que adverse_events, 0025)
-- -----------------------------------------------------------------------------
alter table public.patient_diagnoses enable row level security;

-- SELECT: master (plataforma); admin de la organización; el staff que lo
-- registró; o el clínico asignado al paciente.
drop policy if exists patient_diagnoses_select on public.patient_diagnoses;
create policy patient_diagnoses_select on public.patient_diagnoses
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or staff_id = public.current_staff_id()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patient_diagnoses.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- INSERT: dentro de la propia organización, por un admin de la organización o
-- un clínico asignado al paciente.
drop policy if exists patient_diagnoses_insert on public.patient_diagnoses;
create policy patient_diagnoses_insert on public.patient_diagnoses
  for insert with check (
    organization_id = public.current_organization_id()
    and (
      public.is_admin()
      or exists (
        select 1 from public.staff_patient_assignments spa
        where spa.patient_id = patient_diagnoses.patient_id
          and spa.staff_id = public.current_staff_id()
      )
    )
  );

-- UPDATE: admin de la organización o clínico asignado (cambiar estado,
-- principal, notas...). Se conserva la organización.
drop policy if exists patient_diagnoses_update on public.patient_diagnoses;
create policy patient_diagnoses_update on public.patient_diagnoses
  for update using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patient_diagnoses.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  ) with check (
    organization_id = public.current_organization_id()
  );

-- DELETE: solo admin de la organización (registro clínico; el clínico no borra,
-- marca "descartado").
drop policy if exists patient_diagnoses_admin_delete on public.patient_diagnoses;
create policy patient_diagnoses_admin_delete on public.patient_diagnoses
  for delete using (
    public.is_admin() and organization_id = public.current_organization_id()
  );

-- -----------------------------------------------------------------------------
-- 4. Auditoría (dato clínico del expediente, mismo patrón que 0002/0030)
-- -----------------------------------------------------------------------------
drop trigger if exists trg_audit_patient_diagnoses on public.patient_diagnoses;
create trigger trg_audit_patient_diagnoses
  after insert or update or delete on public.patient_diagnoses
  for each row execute function public.audit_trigger_fn();
