-- =============================================================================
-- 0070_patient_labs.sql — Laboratorios del paciente (ligados al motor)
-- =============================================================================
-- Laboratorios relevantes para la cicatrización (evidencia: glucosa >180,
-- albúmina/nutrición, saturación de O2, etc.). Se registran a nivel PACIENTE
-- con fecha; el motor usa los MÁS RECIENTES (albúmina ya tenía regla; glucosa
-- y O2 se conectan como factores — pesos en validación clínica).
--
-- RLS ADITIVA, mismo patrón que patients: SELECT por organización/master;
-- escritura por personal (admin o staff) de la propia organización, o master.
-- =============================================================================

create table if not exists public.patient_labs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  taken_at date not null default (now() at time zone 'utc')::date,
  glucose_mg_dl numeric(6, 1),
  hba1c_pct numeric(4, 1),
  albumin_g_dl numeric(4, 2),
  hemoglobin_g_dl numeric(4, 1),
  o2_saturation_pct numeric(4, 1),
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_patient_labs_patient
  on public.patient_labs(patient_id, taken_at desc);

alter table public.patient_labs enable row level security;

drop policy if exists patient_labs_select on public.patient_labs;
create policy patient_labs_select on public.patient_labs
  for select using (
    public.is_master()
    or organization_id = public.current_organization_id()
  );

drop policy if exists patient_labs_insert on public.patient_labs;
create policy patient_labs_insert on public.patient_labs
  for insert with check (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );

drop policy if exists patient_labs_delete on public.patient_labs;
create policy patient_labs_delete on public.patient_labs
  for delete using (
    public.is_master()
    or (organization_id = public.current_organization_id()
        and (public.is_admin() or public.current_staff_id() is not null))
  );
