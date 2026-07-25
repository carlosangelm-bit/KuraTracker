-- =============================================================================
-- 0047_insumos_module.sql — Licencia premium del módulo de Insumos (por centro)
-- =============================================================================
-- El módulo de Insumos/Tienda tiene una parte BASE (catálogo de la tienda Shopify
-- + carrito → checkout) que NO requiere premium, y funciones AVANZADAS (mapeo
-- insumo↔producto, inventario, costeo por paciente, reabasto) que sí. Como el
-- inventario/costeo es del CENTRO (no de una cuenta), la licencia premium se
-- modela como una bandera POR ORGANIZACIÓN, activable solo por el master.
-- (Independiente de profiles.premium_enabled, que gatea el Protocolo Kura+.)
-- =============================================================================

alter table public.organizations
  add column if not exists premium_insumos boolean not null default false;

comment on column public.organizations.premium_insumos is
  'Licencia premium del módulo de Insumos: habilita mapeo insumo↔producto, '
  'inventario, costeo por paciente y reabasto. La tienda base no la requiere.';

-- El master fija la licencia sin abrir UPDATE directo de organizations (mismo
-- patrón que set_org_branding / set_shift_config).
create or replace function public.set_org_premium_insumos(p_org uuid, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_master() then
    raise exception 'Solo el master puede cambiar la licencia premium de Insumos';
  end if;
  update public.organizations set premium_insumos = p_enabled where id = p_org;
end;
$$;

grant execute on function public.set_org_premium_insumos(uuid, boolean) to authenticated;
