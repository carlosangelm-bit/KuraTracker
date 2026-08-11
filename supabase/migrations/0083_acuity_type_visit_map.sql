-- =============================================================================
-- 0083_acuity_type_visit_map.sql — Mapeo tipo de cita de Acuity → tipo de visita
-- =============================================================================
-- Cada TIPO de cita del catálogo de Acuity se mapea a un tipo de consulta Kura:
-- 'valoracion' o 'seguimiento'. Con esto, al iniciar una consulta desde una cita
-- el sistema decide el tipo por el tipo de la cita (no lo elige el usuario); y al
-- crear una consulta directa en KuraTracker el usuario elige un tipo de Acuity y
-- ese tipo define valoración/seguimiento.
--
-- La cita entrante solo guarda el NOMBRE del tipo (appointment_type), así que el
-- mapa se llavea por NOMBRE del tipo: { "<nombre del tipo>": "valoracion" | "seguimiento" }.
--
-- RPC set_acuity_type_visit_map: master o admin del propio centro (mismo gate que
-- set_acuity_session_type, 0080). Aditivo; no toca RLS.
-- =============================================================================

alter table public.organizations
  add column if not exists acuity_type_visit_map jsonb not null default '{}'::jsonb;

comment on column public.organizations.acuity_type_visit_map is
  'Mapa nombre de tipo de cita de Acuity → tipo de visita Kura (valoracion|seguimiento). {} = sin mapear.';

create or replace function public.set_acuity_type_visit_map(p_org uuid, p_map jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.is_master()
          or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado para configurar los tipos de consulta de este centro';
  end if;
  update public.organizations
    set acuity_type_visit_map = coalesce(p_map, '{}'::jsonb)
    where id = p_org;
end;
$$;

grant execute on function public.set_acuity_type_visit_map(uuid, jsonb) to authenticated;
