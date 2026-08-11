-- =============================================================================
-- 0085_enabled_scales.sql — Escalas del protocolo de hospital habilitadas por centro
-- =============================================================================
-- El admin del centro elige QUÉ escalas (del catálogo del módulo de
-- hospitalización) participan en su protocolo. El motor de aplicabilidad filtra:
-- una escala no habilitada nunca se ofrece en "Escalas a realizar", aunque el
-- triage la dispararía.
--
-- enabled_scales = arreglo jsonb de scale_id (["GLOBIAD","PUSH",...]).
-- NULL = todas habilitadas (default; centros que no configuran nada).
--
-- RPC set_enabled_scales: master o admin del propio centro (mismo gate que
-- set_shift_config / set_acuity_type_visit_map). Aditivo; no toca RLS.
-- =============================================================================

alter table public.organizations
  add column if not exists enabled_scales jsonb;

comment on column public.organizations.enabled_scales is
  'Escalas del módulo de hospitalización habilitadas en el protocolo del centro '
  '(arreglo de scale_id). NULL = todas.';

create or replace function public.set_enabled_scales(p_org uuid, p_scales jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.is_master()
          or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado para configurar las escalas de este centro';
  end if;
  update public.organizations set enabled_scales = p_scales where id = p_org;
end;
$$;

grant execute on function public.set_enabled_scales(uuid, jsonb) to authenticated;
