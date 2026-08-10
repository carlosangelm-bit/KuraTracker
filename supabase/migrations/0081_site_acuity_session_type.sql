-- =============================================================================
-- 0081_site_acuity_session_type.sql — Tipo de cita de Acuity POR SITIO
-- =============================================================================
-- Un centro (organización) puede tener varios SITIOS; el tipo de cita de Acuity
-- para las sesiones del plan se configura POR SITIO, y lo administra el admin del
-- centro (0080 lo dejó a nivel organización; esto lo baja a sitio, que es el
-- nivel correcto). El nivel organización queda como fallback.
--
-- RPC set_site_acuity_session_type: master o admin del centro dueño del sitio.
-- Aditivo; no toca RLS.
-- =============================================================================

alter table public.sites
  add column if not exists acuity_session_type_id bigint;

comment on column public.sites.acuity_session_type_id is
  'appointmentType de Acuity con el que se agendan las sesiones del plan en ESTE sitio. NULL = hereda el del centro / no configurado.';

create or replace function public.set_site_acuity_session_type(
  p_site uuid, p_type_id bigint
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.is_master()
          or (public.is_admin() and exists (
                select 1 from public.sites s
                where s.id = p_site
                  and s.organization_id = public.current_organization_id()))) then
    raise exception 'No autorizado para configurar el tipo de cita de este sitio';
  end if;
  update public.sites set acuity_session_type_id = p_type_id where id = p_site;
end;
$$;

grant execute on function public.set_site_acuity_session_type(uuid, bigint) to authenticated;
