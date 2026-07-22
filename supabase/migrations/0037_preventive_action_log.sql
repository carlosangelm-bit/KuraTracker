-- 0037_preventive_action_log.sql
--
-- Bitácora de ACCIONES PREVENTIVAS realizadas (módulo de Prevención/Riesgo).
-- El panel-guía sugiere acciones (apósito liberador de presión, ácidos grasos
-- hiperoxigenados, cambios posturales, vigilancia de herida quirúrgica, etc.);
-- cuando el profesional realiza una, la registra aquí para dejar constancia
-- (fecha + autor) y para que el tablero muestre quién ya fue atendido.
--
-- Append-only: cada aplicación es una fila (las medidas preventivas se repiten,
-- p.ej. AGHO 2×/día); la "última aplicación" se deriva por MAX(applied_at).
-- rule_id/action_id referencian el asset prevention_rules.json (no hay FK: el
-- catálogo es reference data en asset). action_label es un SNAPSHOT del texto.
--
-- RLS y auditoría: mismo patrón que 0036/0025 (master / admin de la org /
-- clínico asignado).

create table if not exists public.preventive_action_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  patient_id uuid not null references public.patients(id) on delete cascade,
  rule_id text not null,        -- id de la regla del asset
  action_id text not null,      -- id de la acción dentro de la regla
  action_label text not null,   -- snapshot del texto de la acción
  applied_at timestamptz not null default now(),
  applied_by uuid references public.staff(id),
  notes text,
  created_at timestamptz not null default now()
);

comment on table public.preventive_action_log is
  'Bitácora de acciones preventivas realizadas (apósitos, AGHO, cambios '
  'posturales, vigilancia de herida...). Append-only; referencia rule_id/'
  'action_id del asset prevention_rules.json. Trazabilidad fecha+autor.';

create index if not exists idx_preventive_action_log_organization_id
  on public.preventive_action_log(organization_id);
create index if not exists idx_preventive_action_log_patient_id
  on public.preventive_action_log(patient_id);
create index if not exists idx_preventive_action_log_patient_action
  on public.preventive_action_log(patient_id, rule_id, action_id);

alter table public.preventive_action_log enable row level security;

drop policy if exists preventive_action_log_select on public.preventive_action_log;
create policy preventive_action_log_select on public.preventive_action_log
  for select using (
    public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = preventive_action_log.patient_id
        and spa.staff_id = public.current_staff_id()
    )
  );

drop policy if exists preventive_action_log_insert on public.preventive_action_log;
create policy preventive_action_log_insert on public.preventive_action_log
  for insert with check (
    organization_id = public.current_organization_id()
    and (
      public.is_admin()
      or exists (
        select 1 from public.staff_patient_assignments spa
        where spa.patient_id = preventive_action_log.patient_id
          and spa.staff_id = public.current_staff_id()
      )
    )
  );

-- Solo admin borra (registro clínico; el flujo normal no borra).
drop policy if exists preventive_action_log_admin_delete on public.preventive_action_log;
create policy preventive_action_log_admin_delete on public.preventive_action_log
  for delete using (
    public.is_admin() and organization_id = public.current_organization_id()
  );

drop trigger if exists trg_audit_preventive_action_log on public.preventive_action_log;
create trigger trg_audit_preventive_action_log
  after insert or update or delete on public.preventive_action_log
  for each row execute function public.audit_trigger_fn();
