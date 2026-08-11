-- =============================================================================
-- 0084_scale_assessments.sql — Tabla genérica de valoraciones de escala
-- =============================================================================
-- Fase 0 del módulo de hospitalización: una tabla única para el resultado de
-- CUALQUIER escala clínica puntuable/repetible (GLOBIAD, PUSH, RESVECH, ISTAP,
-- STAR, extravasación, ASEPSIS, …), en el mismo patrón append-only que
-- risk_assessments (Braden). Las clasificaciones por etiología (Wagner/CEAP/
-- NPUAP) siguen viviendo como columnas de `wounds`; esta tabla es para escalas
-- que se aplican una y otra vez y alimentan el motor de prevención.
--
-- Cada fila = una aplicación de una escala. `subscores` guarda las respuestas
-- por ítem; `total_score` para métodos SUMA; `category_result` para CATEGÓRICO
-- (p. ej. GLOBIAD "2A"); `band_id` la banda/interpretación.
--
-- Cambio ADITIVO. RLS espeja risk_assessments (0036) + acceso hospitalario
-- center-wide (0045, has_hospital_org_access).
-- =============================================================================

create table if not exists public.scale_assessments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  patient_id uuid not null references public.patients(id) on delete cascade,
  -- Opcional: la lesión concreta que se valora (NULL si es del paciente, p. ej.
  -- GLOBIAD sobre la piel perineal sin herida registrada).
  wound_id uuid references public.wounds(id) on delete set null,
  scale_id text not null,             -- 'GLOBIAD','PUSH','RESVECH',...
  scale_version text,                 -- versión de la definición (auditoría)
  subscores jsonb,                    -- respuestas por ítem {item_id: valor}
  total_score numeric,                -- métodos SUMA (NULL en CATEGÓRICO)
  category_result text,               -- métodos CATEGÓRICO (p. ej. '2A')
  band_id text,                       -- banda/interpretación resultante
  assessed_at timestamptz not null default now(),
  assessed_by uuid references public.staff(id),
  notes text,
  created_at timestamptz not null default now()
);

comment on table public.scale_assessments is
  'Valoraciones de escala clínica (append-only). Una fila por aplicación de una '
  'escala (GLOBIAD, PUSH, RESVECH, …). Alimenta el motor de prevención.';

create index if not exists idx_scale_assessments_patient
  on public.scale_assessments(patient_id);
create index if not exists idx_scale_assessments_org
  on public.scale_assessments(organization_id);
create index if not exists idx_scale_assessments_scale
  on public.scale_assessments(scale_id);

alter table public.scale_assessments enable row level security;

-- Acceso clínico (espeja risk_assessments 0036): master, admin del centro, o
-- staff asignado al paciente.
drop policy if exists scale_assessments_select on public.scale_assessments;
create policy scale_assessments_select on public.scale_assessments
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = scale_assessments.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );
drop policy if exists scale_assessments_insert on public.scale_assessments;
create policy scale_assessments_insert on public.scale_assessments
  for insert with check (
    organization_id = public.current_organization_id()
    and (
      public.is_admin()
      or exists (
        select 1 from public.staff_patient_assignments spa
        where spa.patient_id = scale_assessments.patient_id
          and spa.staff_id = public.current_staff_id()
      )
    )
  );
drop policy if exists scale_assessments_admin_delete on public.scale_assessments;
create policy scale_assessments_admin_delete on public.scale_assessments
  for delete using (
    public.is_admin() and organization_id = public.current_organization_id()
  );

-- Acceso HOSPITALARIO center-wide (espeja 0045): cualquier staff del centro
-- hospital ve; clínico y enfermería registran.
drop policy if exists scale_assessments_hospital_select on public.scale_assessments;
create policy scale_assessments_hospital_select on public.scale_assessments
  for select using (public.has_hospital_org_access(patient_id));
drop policy if exists scale_assessments_hospital_insert on public.scale_assessments;
create policy scale_assessments_hospital_insert on public.scale_assessments
  for insert with check (
    public.has_hospital_org_access(patient_id)
    and public.current_user_role()::text in ('clinico', 'enfermeria')
  );
