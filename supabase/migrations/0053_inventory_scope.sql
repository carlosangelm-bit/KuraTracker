-- =============================================================================
-- 0053_inventory_scope.sql — Alcance de inventario configurable (Fase E)
-- =============================================================================
-- El centro decide si lleva el inventario POR SITIO (default, cada sitio sus
-- existencias) o POR CENTRO (una sola bolsa para todo el centro). En modo
-- 'center' la app oculta el selector de sitio y usa el sitio principal como
-- bolsa única. Lo fija el admin del centro o el master (patrón set_scheduling_mode).
-- =============================================================================

alter table public.organizations
  add column if not exists inventory_scope text not null default 'site';  -- site | center

comment on column public.organizations.inventory_scope is
  'Alcance del inventario de Insumos: site (por sitio) | center (una bolsa por centro).';

create or replace function public.set_org_inventory_scope(p_org uuid, p_scope text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_scope not in ('site', 'center') then
    raise exception 'inventory_scope inválido: %', p_scope;
  end if;
  if not (public.is_master()
          or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado para configurar el inventario de este centro';
  end if;
  update public.organizations set inventory_scope = p_scope where id = p_org;
end;
$$;

grant execute on function public.set_org_inventory_scope(uuid, text) to authenticated;
