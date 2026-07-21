-- 0026_consents.sql
--
-- CONSENTIMIENTOS DIGITALES del paciente (Protocolos "Expedientes clínicos" y
-- "Desbridamiento"). Registra el consentimiento informado por tipo:
--   privacidad     -> aviso de privacidad / tratamiento de datos.
--   fotografia     -> autorización de toma y uso de fotografía clínica.
--   desbridamiento -> consentimiento específico del procedimiento de
--                     desbridamiento.
--
-- Gating (aplicado en la app): la valoración y la toma de fotografía requieren
-- los consentimientos de privacidad + fotografía registrados (granted=true);
-- el desbridamiento requiere su propio consentimiento. Ver DataRepository.
--
-- RLS: patient-scoped, mismo patrón que el resto del esquema clínico. Un admin
-- gestiona los consentimientos de los pacientes de SU organización (join a
-- patients.organization_id); un clínico, los de sus pacientes asignados
-- (staff_patient_assignments). Se audita (dato regulatorio del expediente).

-- -----------------------------------------------------------------------------
-- 1. Tipo de consentimiento
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'consent_type') then
    create type public.consent_type as enum
      ('privacidad', 'fotografia', 'desbridamiento');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 2. Tabla consents
-- -----------------------------------------------------------------------------
create table if not exists public.consents (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  type public.consent_type not null,
  granted boolean not null default false,
  granted_at timestamptz,
  -- Quién firma/otorga el consentimiento (paciente, tutor o representante).
  signed_by text,
  -- Referencia al documento físico/escaneado que respalda el consentimiento
  -- (folio, URL de storage, etc.).
  doc_ref text,
  created_at timestamptz not null default now(),
  -- Un consentimiento vigente por (paciente, tipo); el historial de cambios
  -- queda en audit_log vía el trigger de auditoría.
  unique (patient_id, type)
);

comment on table public.consents is
  'Consentimientos informados del paciente por tipo (privacidad/fotografia/'
  'desbridamiento). granted=true habilita el gating de valoración, fotografía '
  'y desbridamiento en la app (Protocolos "Expedientes clínicos" y '
  '"Desbridamiento").';

create index if not exists idx_consents_patient_id
  on public.consents(patient_id);

-- -----------------------------------------------------------------------------
-- 3. RLS (patient-scoped)
-- -----------------------------------------------------------------------------
alter table public.consents enable row level security;

drop policy if exists consents_select on public.consents;
create policy consents_select on public.consents
  for select using (
    public.is_master()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = consents.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or (
      public.is_admin()
      and exists (
        select 1 from public.patients p
        where p.id = consents.patient_id
          and p.organization_id = public.current_organization_id()
      )
    )
  );

drop policy if exists consents_insert on public.consents;
create policy consents_insert on public.consents
  for insert with check (
    exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = consents.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or (
      public.is_admin()
      and exists (
        select 1 from public.patients p
        where p.id = consents.patient_id
          and p.organization_id = public.current_organization_id()
      )
    )
  );

drop policy if exists consents_update on public.consents;
create policy consents_update on public.consents
  for update using (
    exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = consents.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or (
      public.is_admin()
      and exists (
        select 1 from public.patients p
        where p.id = consents.patient_id
          and p.organization_id = public.current_organization_id()
      )
    )
  );

-- DELETE solo admin de la organización (registro del expediente).
drop policy if exists consents_admin_delete on public.consents;
create policy consents_admin_delete on public.consents
  for delete using (
    public.is_admin()
    and exists (
      select 1 from public.patients p
      where p.id = consents.patient_id
        and p.organization_id = public.current_organization_id()
    )
  );

-- -----------------------------------------------------------------------------
-- 4. Auditoría (dato regulatorio del expediente)
-- -----------------------------------------------------------------------------
drop trigger if exists trg_audit_consents on public.consents;
create trigger trg_audit_consents
  after insert or update or delete on public.consents
  for each row execute function public.audit_trigger_fn();
