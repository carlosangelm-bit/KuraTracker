-- 0021_set_scheduling_mode_rpc.sql
--
-- Fix: el admin de un centro no podía activar su modo de agenda. La RLS de
-- `organizations` solo permite UPDATE al master (organizations_master_update,
-- 0012), así que el UPDATE directo de scheduling_mode desde la app (admin del
-- centro) era rechazado por RLS y el `.single()` del cliente fallaba (406).
--
-- Solución acotada: un RPC security-definer que SOLO cambia scheduling_mode y
-- valida rol + pertenencia al centro. No se abre una policy de UPDATE amplia en
-- organizations (evita que el admin edite name/is_active de su centro).

create or replace function public.set_scheduling_mode(p_org uuid, p_mode text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_mode not in ('none', 'manual', 'acuity') then
    raise exception 'Modo de agenda inválido: %', p_mode;
  end if;
  -- Solo el master (cualquier centro) o el admin de ESE centro.
  if not (
    public.is_master()
    or (public.is_admin() and p_org = public.current_organization_id())
  ) then
    raise exception 'No autorizado para cambiar el modo de agenda de este centro.';
  end if;
  update public.organizations set scheduling_mode = p_mode where id = p_org;
end;
$$;

comment on function public.set_scheduling_mode(uuid, text) is
  'Cambia organizations.scheduling_mode (none|manual|acuity) del centro indicado. '
  'Security definer + validación de rol/centro: permite al admin del propio '
  'centro (o al master) activar su modo de agenda sin abrir UPDATE general de '
  'organizations. Ver 0020/0021.';

grant execute on function public.set_scheduling_mode(uuid, text) to authenticated;
