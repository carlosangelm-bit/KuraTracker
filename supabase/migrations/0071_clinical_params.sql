-- 0071_clinical_params.sql
-- Parámetros clínicos del motor de reglas de tratamiento (data-driven, Fase A).
-- Tabla GLOBAL de plataforma (no por centro): guarda los JSON de umbrales
-- (thresholds) y mapeos (archetypes) que hoy viven en assets/engine/clinical/.
-- El motor los lee de aquí (con fallback al asset horneado si la tabla está
-- vacía). Versionado por fila para auditoría: cada carga de María es una fila
-- nueva; el motor usa la más reciente (uploaded_at desc).
--
-- Seguridad: lectura para cualquier usuario autenticado (el motor la consume
-- en todos los roles); ESCRITURA solo master, exclusivamente vía el RPC
-- set_clinical_params (SECURITY DEFINER). RLS ADITIVA: no toca ninguna policy
-- existente.

create table if not exists public.clinical_params (
  id uuid primary key default gen_random_uuid(),
  thresholds jsonb not null,
  archetypes jsonb not null,
  version text not null,
  uploaded_by uuid references auth.users(id),
  uploaded_at timestamptz not null default now()
);

comment on table public.clinical_params is
  'Parámetros clínicos del motor (umbrales/mapeos). Global. Escribe solo master vía set_clinical_params; el motor usa la fila más reciente.';

create index if not exists clinical_params_uploaded_at_idx
  on public.clinical_params (uploaded_at desc);

alter table public.clinical_params enable row level security;

-- Lectura: cualquier usuario autenticado (el motor necesita los parámetros en
-- todos los roles). No expone datos de paciente: son parámetros de reglas.
drop policy if exists clinical_params_select_authenticated on public.clinical_params;
create policy clinical_params_select_authenticated
  on public.clinical_params
  for select
  using (auth.uid() is not null);

-- Escritura: sin policies de insert/update/delete => denegada por defecto para
-- el cliente. El único camino es el RPC de abajo (SECURITY DEFINER), gated a
-- master, siguiendo el patrón de set_shift_config/set_org_branding.

create or replace function public.set_clinical_params(
  p_thresholds jsonb,
  p_archetypes jsonb,
  p_version text
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not public.is_master() then
    raise exception 'Solo el master puede modificar los parámetros clínicos';
  end if;
  insert into public.clinical_params (thresholds, archetypes, version, uploaded_by)
  values (p_thresholds, p_archetypes, p_version, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.set_clinical_params(jsonb, jsonb, text) to authenticated;
