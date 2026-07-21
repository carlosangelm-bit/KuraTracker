-- 0029_referrals.sql
--
-- FORMATO DE REFERENCIA / INTERCONSULTA (Prompt 6). Registra las referencias a
-- especialistas: paciente, herida/consulta de origen, especialidad, motivo,
-- checklist de adjuntos (reporte eKare, resumen clínico, cultivo, ITB,
-- laboratorios), firma del profesional que refiere, y la captura del documento
-- de RETORNO del especialista al expediente.
--
-- RLS patient-scoped (mismo patrón que consents/adverse_events): master /
-- clínico asignado / admin de la organización (join a patients). Se audita.
--
-- Numerada 0029 para no colisionar con migraciones pendientes de otras ramas
-- sin fusionar (0025 eventos adversos, 0026/0027 consentimientos+firma, 0028
-- clasificaciones por etiología).

-- -----------------------------------------------------------------------------
-- 1. Estado de la referencia
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'referral_status') then
    create type public.referral_status as enum ('enviada', 'respondida', 'cerrada');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 2. Tabla referrals
-- -----------------------------------------------------------------------------
create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  wound_id uuid references public.wounds(id) on delete set null,
  consultation_id uuid references public.consultations(id) on delete set null,
  -- Profesional que refiere (nullable: admin de licencia individual sin staff).
  staff_id uuid references public.staff(id),
  especialidad text not null,
  motivo text not null,
  -- Checklist de adjuntos como objeto JSON booleano: reporte_ekare,
  -- resumen_clinico, cultivo, itb, laboratorios (extensible sin migración).
  adjuntos jsonb not null default '{}'::jsonb,
  status public.referral_status not null default 'enviada',
  -- Firma (nombre + cédula) del profesional que refiere, congelada en el doc.
  referral_signed_by text,
  referral_signed_license text,
  -- Captura del documento de RETORNO del especialista.
  return_doc_ref text,     -- folio / URL de storage del documento de respuesta
  return_notes text,       -- resumen de la respuesta del especialista
  returned_at timestamptz, -- cuándo se registró la respuesta
  created_at timestamptz not null default now()
);

comment on table public.referrals is
  'Formato de referencia/interconsulta a especialista (Prompt 6) + captura del '
  'documento de retorno. adjuntos jsonb = checklist (reporte_ekare, '
  'resumen_clinico, cultivo, itb, laboratorios).';

create index if not exists idx_referrals_patient_id
  on public.referrals(patient_id);
create index if not exists idx_referrals_wound_id
  on public.referrals(wound_id);
create index if not exists idx_referrals_status
  on public.referrals(status);

-- -----------------------------------------------------------------------------
-- 3. RLS (patient-scoped)
-- -----------------------------------------------------------------------------
alter table public.referrals enable row level security;

drop policy if exists referrals_select on public.referrals;
create policy referrals_select on public.referrals
  for select using (
    public.is_master()
    or staff_id = public.current_staff_id()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = referrals.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or (
      public.is_admin()
      and exists (
        select 1 from public.patients p
        where p.id = referrals.patient_id
          and p.organization_id = public.current_organization_id()
      )
    )
  );

drop policy if exists referrals_insert on public.referrals;
create policy referrals_insert on public.referrals
  for insert with check (
    exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = referrals.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or (
      public.is_admin()
      and exists (
        select 1 from public.patients p
        where p.id = referrals.patient_id
          and p.organization_id = public.current_organization_id()
      )
    )
  );

drop policy if exists referrals_update on public.referrals;
create policy referrals_update on public.referrals
  for update using (
    staff_id = public.current_staff_id()
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = referrals.patient_id
        and spa.staff_id = public.current_staff_id()
    )
    or (
      public.is_admin()
      and exists (
        select 1 from public.patients p
        where p.id = referrals.patient_id
          and p.organization_id = public.current_organization_id()
      )
    )
  );

drop policy if exists referrals_admin_delete on public.referrals;
create policy referrals_admin_delete on public.referrals
  for delete using (
    public.is_admin()
    and exists (
      select 1 from public.patients p
      where p.id = referrals.patient_id
        and p.organization_id = public.current_organization_id()
    )
  );

-- -----------------------------------------------------------------------------
-- 4. Auditoría (documento del expediente)
-- -----------------------------------------------------------------------------
drop trigger if exists trg_audit_referrals on public.referrals;
create trigger trg_audit_referrals
  after insert or update or delete on public.referrals
  for each row execute function public.audit_trigger_fn();
