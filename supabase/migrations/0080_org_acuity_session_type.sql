-- =============================================================================
-- 0080_org_acuity_session_type.sql — Tipo de cita de Acuity para las sesiones
-- =============================================================================
-- Al empujar las sesiones del plan a Acuity (fuente de verdad), cada cita se
-- crea con un appointmentType. El centro elige, una vez, qué tipo de Acuity
-- representa una "sesión de curación/seguimiento". Se guarda aquí.
--
-- RPC set_acuity_session_type: master o admin del propio centro (mismo gate que
-- set_mp_point_device, 0074). Aditivo; no toca RLS.
-- =============================================================================

alter table public.organizations
  add column if not exists acuity_session_type_id bigint;

comment on column public.organizations.acuity_session_type_id is
  'appointmentType de Acuity con el que se agendan las sesiones del plan de tratamiento. NULL = no configurado.';

create or replace function public.set_acuity_session_type(p_org uuid, p_type_id bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.is_master()
          or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado para configurar el tipo de cita de este centro';
  end if;
  update public.organizations set acuity_session_type_id = p_type_id where id = p_org;
end;
$$;

grant execute on function public.set_acuity_session_type(uuid, bigint) to authenticated;
