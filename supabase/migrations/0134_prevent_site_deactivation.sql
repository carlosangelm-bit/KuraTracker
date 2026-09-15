-- =============================================================================
-- 0134_prevent_site_deactivation.sql
-- =============================================================================
-- Guardia "no desactivar un sitio que rompe el centro" (Admin del centro — Sitios,
-- §5). Desactivar un sitio (is_active true → false) se RECHAZA en tres casos, cada uno
-- con un mensaje que dice qué hacer:
--
--   1) Es el ÚNICO sitio activo del centro. `consultations.site_id` es NOT NULL, así
--      que sin ningún sitio activo el centro no puede registrar una sola consulta.
--   2) Tiene PERSONAL ACTIVO con `primary_site_id` apuntando a él.
--   3) Tiene EXISTENCIAS de inventario distintas de cero (algún artículo con neto <> 0).
--
-- La app ya lo valida en cliente (setSiteActive); esto lo hace cumplir también del lado
-- servidor, para el acceso directo por PostgREST — mismo precedente que
-- 0111_prevent_org_without_clinico.sql: una guardia que solo vive en la app no está
-- cuando importa. Los mensajes del servidor y del cliente dicen LO MISMO.
--
-- El trigger corre como `trg_zz_*` para dispararse al final (Postgres ordena los BEFORE
-- por nombre). La función es SECURITY DEFINER con `set search_path = public` para contar
-- sitios/personal/movimientos del centro sin depender de la RLS del que llama. Solo
-- actúa en la transición true → false; reactivar y los no-ops se permiten.
-- =============================================================================

create or replace function public.prevent_site_deactivation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_count integer;
begin
  -- Solo al DESACTIVAR un sitio que estaba activo. Reactivar (false → true) y los
  -- updates que no tocan is_active (renombrar, cambiar tipo/dirección) pasan.
  if not (old.is_active and not new.is_active) then
    return new;
  end if;

  -- 1) ¿Es el único sitio activo del centro?
  if not exists (
    select 1
    from public.sites s
    where s.organization_id = old.organization_id
      and s.id <> old.id
      and s.is_active = true
  ) then
    raise exception 'No puedes desactivar este sitio: es el único activo del centro y toda consulta necesita un sitio. Da de alta otro antes de desactivar este.';
  end if;

  -- 2) ¿Tiene personal ACTIVO con este sitio como principal?
  select count(*) into v_staff_count
  from public.staff st
  where st.primary_site_id = old.id
    and st.is_active = true;
  if v_staff_count > 0 then
    raise exception 'No puedes desactivar este sitio: % personas lo tienen como sitio principal. Reasígnalas en Personal antes de desactivarlo.', v_staff_count;
  end if;

  -- 3) ¿Tiene existencias de inventario distintas de cero?
  if exists (
    select 1
    from public.inventory_movements im
    where im.site_id = old.id
    group by im.inventory_item_id
    having sum(im.delta) <> 0
  ) then
    raise exception 'No puedes desactivar este sitio: tiene existencias en inventario. Trasládalas o ajústalas a cero antes.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_zz_prevent_site_deactivation on public.sites;
create trigger trg_zz_prevent_site_deactivation
  before update on public.sites
  for each row execute function public.prevent_site_deactivation();
