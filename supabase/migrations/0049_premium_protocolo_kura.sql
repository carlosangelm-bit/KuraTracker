-- =============================================================================
-- 0049_premium_protocolo_kura.sql — Kura+ como módulo premium POR CENTRO
-- =============================================================================
-- Las funciones premium se ofrecen como MÓDULOS ADD-ON independientes que se
-- añaden a la licencia del CENTRO. Ya existe organizations.premium_insumos (0047)
-- para el módulo de Insumos; aquí se añade el del "Protocolo Kura+".
--
-- Es ADITIVO: el gate del Protocolo Kura+ era por usuario (profiles.premium_enabled)
-- y se conserva; la app usará el OR de ambos (usuario premium O centro con el
-- add-on Kura+), de modo que activar el módulo en el centro lo habilita para todo
-- el centro sin quitar la activación por usuario que ya existía.
-- =============================================================================

alter table public.organizations
  add column if not exists premium_protocolo_kura boolean not null default false;

comment on column public.organizations.premium_protocolo_kura is
  'Add-on premium "Protocolo Kura+" a nivel centro. La app lo combina (OR) con '
  'profiles.premium_enabled (gate por usuario, que se conserva).';

create or replace function public.set_org_premium_protocolo_kura(p_org uuid, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_master() then
    raise exception 'Solo el master puede cambiar la licencia del Protocolo Kura+';
  end if;
  update public.organizations set premium_protocolo_kura = p_enabled where id = p_org;
end;
$$;

grant execute on function public.set_org_premium_protocolo_kura(uuid, boolean) to authenticated;
