-- 0033_clinical_amendments.sql
--
-- FASE 4 de cumplimiento (NOM-004/024): INMUTABILIDAD y notas de ENMIENDA.
-- La norma prohíbe borrar/sobrescribir una nota clínica firmada; las
-- correcciones se hacen mediante una NOTA DE ENMIENDA/ACLARACIÓN append-only,
-- fechada y firmada, ligada a la nota original — nunca editando el original.
--
-- 1) Tabla clinical_amendments: enmiendas/aclaraciones a una consulta (nota).
--    Es ella misma inmutable: solo INSERT + SELECT (sin UPDATE ni DELETE).
-- 2) Hardening: se quita la capacidad de BORRADO de las tablas clínicas nuevas
--    (adverse_events, consents, referrals). Un dato equivocado se corrige con
--    enmienda / cambio de estado, no se elimina. (La bitácora audit_log ya es
--    inalterable desde 0002/0003.)

-- -----------------------------------------------------------------------------
-- 1. Tabla de enmiendas
-- -----------------------------------------------------------------------------
create table if not exists public.clinical_amendments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  -- Nota original enmendada (la consulta). Nullable por si a futuro se enmienda
  -- otro tipo de registro.
  consultation_id uuid references public.consultations(id) on delete cascade,
  body text not null,          -- texto de la aclaración/corrección
  reason text,                 -- motivo de la enmienda
  staff_id uuid references public.staff(id),
  signed_by text,              -- firma: nombre del profesional
  signed_license text,         -- cédula profesional
  created_at timestamptz not null default now()
);

comment on table public.clinical_amendments is
  'Notas de enmienda/aclaración (NOM-004). Append-only e inmutables: corrigen '
  'una nota clínica SIN sobrescribir el original. Solo INSERT/SELECT por RLS.';

create index if not exists idx_clinical_amendments_patient_id
  on public.clinical_amendments(patient_id);
create index if not exists idx_clinical_amendments_consultation_id
  on public.clinical_amendments(consultation_id);

alter table public.clinical_amendments enable row level security;

drop policy if exists clinical_amendments_select on public.clinical_amendments;
create policy clinical_amendments_select on public.clinical_amendments
  for select using (
    public.is_master()
    or staff_id = public.current_staff_id()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = clinical_amendments.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or (
      public.is_admin()
      and exists (
        select 1 from public.patients p
        where p.id = clinical_amendments.patient_id
          and p.organization_id = public.current_organization_id()
      )
    )
  );

drop policy if exists clinical_amendments_insert on public.clinical_amendments;
create policy clinical_amendments_insert on public.clinical_amendments
  for insert with check (
    exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = clinical_amendments.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or (
      public.is_admin()
      and exists (
        select 1 from public.patients p
        where p.id = clinical_amendments.patient_id
          and p.organization_id = public.current_organization_id()
      )
    )
  );

-- SIN policy de UPDATE ni DELETE: una enmienda no se edita ni se borra
-- (append-only). Si hubo error en una enmienda, se agrega otra.

drop trigger if exists trg_audit_clinical_amendments on public.clinical_amendments;
create trigger trg_audit_clinical_amendments
  after insert or update or delete on public.clinical_amendments
  for each row execute function public.audit_trigger_fn();

-- -----------------------------------------------------------------------------
-- 2. Hardening: quitar el borrado de las tablas clínicas nuevas
-- -----------------------------------------------------------------------------
-- Sin policy de DELETE => ningún cliente puede borrar (solo service_role para
-- operaciones administrativas de BD). Alinea con la inmutabilidad del
-- expediente: los datos se corrigen (enmienda) o cambian de estado, no se
-- eliminan.
drop policy if exists adverse_events_admin_delete on public.adverse_events;
drop policy if exists consents_admin_delete on public.consents;
drop policy if exists referrals_admin_delete on public.referrals;
