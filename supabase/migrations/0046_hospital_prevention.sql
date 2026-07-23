-- =============================================================================
-- 0046_hospital_prevention.sql — Ubicación (piso/área) + turnos configurables
-- =============================================================================
-- Módulo de Prevención Hospitalaria: la ubicación del paciente se estructura en
-- piso · área · cama (bed ya existe en patient_admissions), y el centro puede
-- configurar sus TURNOS para la ventana de cumplimiento y los cortes del
-- dashboard. Sin turnos configurados = ventana de 24 h por defecto (en la app).
-- No toca RLS (el acceso hospital center-wide ya lo dio 0045).
-- =============================================================================

alter table public.patient_admissions
  add column if not exists floor text,   -- piso
  add column if not exists area text;    -- área/servicio dentro del piso

comment on column public.patient_admissions.floor is 'Piso (prevención hospitalaria).';
comment on column public.patient_admissions.area is 'Área/servicio dentro del piso.';

-- Turnos del centro (opcional). null = ventana de 24 h. Formato:
-- [{"name":"Mañana","startHour":7,"endHour":15}, ...] (endHour < startHour = cruza medianoche).
alter table public.organizations
  add column if not exists shift_config jsonb;

comment on column public.organizations.shift_config is
  'Turnos del centro para la ventana de cumplimiento de prevención hospitalaria '
  '(lista [{name,startHour,endHour}]). null = ventana de 24 h.';

-- RPC para que el admin del centro (o master) fije sus turnos sin abrir UPDATE
-- directo de organizations (misma técnica que set_scheduling_mode / set_org_branding).
create or replace function public.set_shift_config(p_org uuid, p_shifts jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.is_master()
          or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado para configurar turnos de este centro';
  end if;
  update public.organizations set shift_config = p_shifts where id = p_org;
end;
$$;

grant execute on function public.set_shift_config(uuid, jsonb) to authenticated;
