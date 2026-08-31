-- =============================================================================
-- 0101_data_disclosures.sql — Registro de divulgaciones de datos clínicos.
-- =============================================================================
-- Toda salida de datos del centro (CSV de mediciones, CSV de consultas,
-- expediente de un paciente, entrega completa del centro) deja una fila aquí.
-- NO es la bitácora de cambios (audit_log): esa registra modificaciones; esta
-- registra qué SALIÓ de la plataforma, cuándo y por mano de quién.
-- =============================================================================

create table if not exists public.data_disclosures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  actor_id uuid references auth.users(id),
  actor_email text,                 -- desnormalizado a propósito: el registro debe
                                    -- seguir siendo legible si el perfil se borra
  kind text not null,               -- 'csv_mediciones' | 'csv_consultas'
                                    -- | 'expediente_paciente' | 'entrega_centro'
  scope jsonb,                      -- filtros aplicados: patient_id, rango de fechas, etc.
  record_count integer,             -- filas (CSV) o archivos (ZIP)
  patient_count integer,
  photo_count integer,
  missing_count integer,            -- fotos/registros que no se pudieron incluir
  file_name text,
  occurred_at timestamptz not null default now()
);

create index if not exists idx_data_disclosures_org
  on public.data_disclosures(organization_id, occurred_at desc);

comment on table public.data_disclosures is
  'Registro de divulgaciones: qué datos clínicos SALIERON de la plataforma, cuándo '
  'y por mano de quién. Distinto de audit_log (que registra cambios). Inmutable: '
  'un registro de divulgación que se puede editar no sirve de nada.';

-- RLS
alter table public.data_disclosures enable row level security;

-- Insert: cualquier miembro autenticado, para SU organización activa.
drop policy if exists data_disclosures_insert on public.data_disclosures;
create policy data_disclosures_insert on public.data_disclosures
  for insert with check (organization_id = public.current_organization_id());

-- Select: admin de esa organización, y master.
drop policy if exists data_disclosures_select on public.data_disclosures;
create policy data_disclosures_select on public.data_disclosures
  for select using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );

-- Inmutabilidad: ni UPDATE ni DELETE, para nadie. Mismo patrón que el 0097.
create or replace function public.prevent_disclosure_change()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception 'Registro de divulgación: es inmutable.';
end; $$;

drop trigger if exists trg_prevent_disclosure_change on public.data_disclosures;
create trigger trg_prevent_disclosure_change
  before update or delete on public.data_disclosures
  for each row execute function public.prevent_disclosure_change();
