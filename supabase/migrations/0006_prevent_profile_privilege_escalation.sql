-- 0006: impedir que usuarios no-admin cambien su propio role/premium_enabled
--
-- Hallazgo de seguridad: la politica RLS `profiles_update_own_or_admin`
-- (0003_row_level_security.sql) permite que cualquier usuario autenticado
-- actualice su propia fila en `profiles` sin restriccion de columnas. Esto
-- permite auto-promocion a role='admin' y auto-activacion de
-- premium_enabled=true via una simple llamada PATCH /rest/v1/profiles,
-- sin aprobacion de un administrador.
--
-- `with check` de RLS no puede comparar el valor viejo vs. el nuevo de una
-- fila (solo valida la fila resultante), por lo que la proteccion debe
-- implementarse con un trigger BEFORE UPDATE que tenga acceso a OLD y NEW.
--
-- No se modifican las politicas RLS existentes de 0003 ni se otorgan
-- permisos de INSERT adicionales: esta migracion es puramente aditiva
-- (una funcion + un trigger) y actua como una segunda capa de defensa
-- sobre la politica de UPDATE ya existente.
create or replace function public.prevent_profile_privilege_escalation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Permite cambios en contexto server-side (service_role / SQL Editor,
  -- donde auth.uid() es NULL) y a administradores autenticados.
  if auth.uid() is not null and not public.is_admin() then
    if new.role is distinct from old.role
       or new.premium_enabled is distinct from old.premium_enabled then
      raise exception 'No autorizado: solo un administrador puede modificar role o premium_enabled';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_profile_privilege_escalation on public.profiles;
create trigger trg_prevent_profile_privilege_escalation
  before update on public.profiles
  for each row execute function public.prevent_profile_privilege_escalation();
