-- =============================================================================
-- 0104_prevent_master_self_grant.sql — Cerrar la auto-promoción admin → master.
-- =============================================================================
-- Hueco (lectura del esquema, exposición actual = 0): la policy de UPDATE de
-- profiles (0017) deja a un admin actualizar CUALQUIER fila sin condición de
-- organización, y el guard anti-escalada (0096) EXIME a los admins. Nada en la
-- BD prohíbe otorgar 'master'. Resultado: un admin de un centro cliente podía
-- hacer PATCH a su propia fila con {"roles":["master"]} y la base lo aceptaba —
-- volviéndose administrador de plataforma y leyendo los expedientes de TODOS los
-- centros. La única validación vivía en la Edge Function admin-create-user, es
-- decir en el camino de la app, NO en el límite. En Flutter Web la anon key está
-- en el cliente: la RLS es el límite de seguridad, y ahí faltaba.
--
-- Va ANTES de la migración de roles-por-centro (0105): esa hará que
-- set_active_center copie el conjunto de la membresía al perfil, así que sin el
-- candado de §4.2 abriría una segunda ruta (roles={master} en la propia
-- membresía + switch). Por eso el candado va aquí primero.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 4.1 Guard anti-escalada: nadie otorga/retira 'master' salvo un master.
--     La conducta para un NO-admin queda intacta (solo se agrega la línea del
--     rol master, y se exime también al master de la rama de no-admin).
-- -----------------------------------------------------------------------------
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

  -- NUEVO: el rol `master` solo lo otorga o retira un master.
  if not public.is_master()
     and ( ('master'::public.user_role = any(new.roles))
        <> ('master'::public.user_role = any(old.roles)) ) then
    raise exception 'No autorizado: solo el master puede otorgar o retirar el rol master.';
  end if;

  return new;
end; $$;

-- El trigger ya existe (0006/0012/0040); basta el create or replace de arriba.

-- -----------------------------------------------------------------------------
-- 4.2 El mismo candado en user_center_memberships: 'master' en una membresía
--     solo lo asigna un master. Hoy la membresía usa el rol ESCALAR; cuando
--     0105 agregue el conjunto `roles`, esa migración debe extender el candado
--     al arreglo. Aquí se cubre el escalar.
-- -----------------------------------------------------------------------------
create or replace function public.prevent_membership_master_grant()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if not public.is_master()
     and new.role = 'master'::public.user_role
     and (tg_op = 'INSERT' or old.role is distinct from new.role) then
    raise exception 'No autorizado: solo el master puede asignar el rol master en una membresía.';
  end if;
  return new;
end; $$;

drop trigger if exists trg_prevent_membership_master_grant on public.user_center_memberships;
create trigger trg_prevent_membership_master_grant
  before insert or update on public.user_center_memberships
  for each row execute function public.prevent_membership_master_grant();

-- -----------------------------------------------------------------------------
-- 4.3 Acotar los UPDATE de admin a su propia organización (segundo hueco,
--     independiente del de master): antes un admin del centro A podía modificar
--     perfiles del centro B. El alta de usuarios pasa por la Edge Function con
--     service role (no sujeta a RLS) y set_active_center es SECURITY DEFINER, así
--     que ninguno se ve afectado; los flujos de admin son sobre su propio centro.
-- -----------------------------------------------------------------------------
drop policy if exists profiles_update_own_or_admin on public.profiles;
create policy profiles_update_own_or_admin on public.profiles
  for update using (
    id = auth.uid()
    or public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );
