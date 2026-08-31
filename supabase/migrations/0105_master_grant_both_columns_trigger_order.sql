-- =============================================================================
-- 0105_master_grant_both_columns_trigger_order.sql — Cerrar la ventana que dejó
-- el 0104: la auto-promoción admin→master por el ESPEJO ESCALAR `role`.
-- =============================================================================
-- Postgres dispara los BEFORE UPDATE en orden ALFABÉTICO por nombre de trigger:
--   trg_prevent_profile_privilege_escalation  (candado 0104)
--   trg_profiles_updated_at
--   trg_sync_profile_roles                     (deriva roles ⇆ role)
-- El candado corría ANTES del sync y solo miraba `roles`. Un admin que escribía
-- SOLO el escalar — PATCH {"role":"master"} — pasaba: al correr el candado
-- new.roles == old.roles (XOR falso) y la rama de no-admin se salta porque ES
-- admin. Después el sync hacía `new.roles := array['master']`. El 0104 cerró la
-- puerta y dejó la ventana.
--
-- Dos arreglos, ambos:
--  §3 el candado compara AMBAS columnas (role y roles) — cierra el hueco ya.
--  §4 el candado corre AL FINAL (nombre trg_zz_*), tras las derivaciones, así
--     valida el estado DEFINITIVO y no la entrada cruda — evita que la próxima
--     columna derivada lo reabra.
-- =============================================================================

-- §3 — comparar las dos columnas que representan el mismo dato.
create or replace function public.prevent_profile_privilege_escalation()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then return new; end if;   -- alta por trigger de Auth

  -- Un no-admin no cambia nada de esto (conducta original, intacta).
  if not public.is_admin() and not public.is_master() then
    if new.role is distinct from old.role
       or new.roles is distinct from old.roles
       or new.premium_enabled is distinct from old.premium_enabled then
      raise exception 'No autorizado: solo un administrador puede modificar role/roles o premium_enabled';
    end if;
  end if;

  -- El rol `master` solo lo otorga o retira un master. Se mira el CONJUNTO y el
  -- ESPEJO ESCALAR: escribir cualquiera de los dos queda cubierto.
  if not public.is_master()
     and ( ('master'::public.user_role = any(new.roles))
        <> ('master'::public.user_role = any(old.roles))
       or (new.role = 'master'::public.user_role)
        <> (old.role = 'master'::public.user_role) ) then
    raise exception 'No autorizado: solo el master puede otorgar o retirar el rol master.';
  end if;

  return new;
end; $$;

-- §4 — renombrar el trigger a trg_zz_* para que corra DESPUÉS de trg_sync_*
-- (validación del estado final). Se elimina el nombre viejo del 0104/0040.
drop trigger if exists trg_prevent_profile_privilege_escalation on public.profiles;
drop trigger if exists trg_zz_prevent_profile_privilege_escalation on public.profiles;
create trigger trg_zz_prevent_profile_privilege_escalation
  before update on public.profiles
  for each row execute function public.prevent_profile_privilege_escalation();
