-- =============================================================================
-- 0106_membership_roles_and_seats.sql — Roles POR CENTRO + asientos de licencia.
-- =============================================================================
-- Consolida "roles por centro" y "modelo de licencias". Cierra dos defectos:
--  (a) set_active_center copiaba el rol ESCALAR de la membresía; el atajo de
--      compat del 0098 (role→roles) fabricaba/perdía roles al cambiar de centro
--      (una membresía administrativa en un hospital producía escritura clínica).
--  (b) no había dónde contar asientos (profiles tiene 1 fila y 1 centro activo;
--      el contrato es del centro → la fuente debe ser la membresía).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Esquema
-- -----------------------------------------------------------------------------
alter table public.user_center_memberships
  add column if not exists roles public.user_role[] not null default '{}';

-- Backfill SIN el caso especial de admin: la membresía dice lo que dice.
update public.user_center_memberships
set roles = array[role]
where roles = '{}';

alter table public.user_center_memberships
  add column if not exists seat_exempt boolean not null default false;

comment on column public.user_center_memberships.seat_exempt is
  'true = esta membresia NO consume licencia del centro. Dos casos: personal de '
  'plataforma (master) y personal de Kura+ prestando servicio dentro de un centro '
  'cliente (no debe ocupar un asiento que el cliente pago). Explicito, no inferido '
  'del rol.';

alter table public.organizations
  add column if not exists seats_contracted integer;   -- null = sin limite

-- -----------------------------------------------------------------------------
-- 2. Trigger espejo en la membresía (role ⇆ roles), como sync_profile_roles.
--    NO replica el atajo admin→{admin,clinico} del 0098 (reintroduciría el
--    defecto que esto cierra).
-- -----------------------------------------------------------------------------
create or replace function public.sync_membership_roles()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.roles is null or new.roles = '{}' then
      new.roles := array[new.role];
    else
      new.role := public.primary_role(new.roles);
    end if;
  else
    if new.roles is distinct from old.roles then
      new.role := public.primary_role(new.roles);
    elsif new.role is distinct from old.role then
      new.roles := array[new.role];
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists trg_sync_membership_roles on public.user_center_memberships;
create trigger trg_sync_membership_roles
  before insert or update of role, roles on public.user_center_memberships
  for each row execute function public.sync_membership_roles();

-- -----------------------------------------------------------------------------
-- 3. Candado master en la membresía: mira AMBAS columnas y corre AL FINAL
--    (trg_zz_*, tras el espejo de §2). Reemplaza el de 0104 (que miraba solo el
--    escalar y corría antes del espejo → misma ventana que cerró el 0105).
-- -----------------------------------------------------------------------------
create or replace function public.prevent_membership_master_grant()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  new_has_master boolean := ('master'::public.user_role = any(new.roles))
                            or new.role = 'master'::public.user_role;
  old_has_master boolean := (tg_op = 'UPDATE')
    and ( ('master'::public.user_role = any(old.roles))
          or old.role = 'master'::public.user_role );
begin
  if not public.is_master() and (new_has_master <> old_has_master) then
    raise exception 'No autorizado: solo el master puede asignar el rol master en una membresía.';
  end if;
  return new;
end; $$;

drop trigger if exists trg_prevent_membership_master_grant on public.user_center_memberships;
drop trigger if exists trg_zz_prevent_membership_master_grant on public.user_center_memberships;
create trigger trg_zz_prevent_membership_master_grant
  before insert or update on public.user_center_memberships
  for each row execute function public.prevent_membership_master_grant();

-- -----------------------------------------------------------------------------
-- 4. Guard de profiles: permitir el SWITCH legítimo (cambio de org+roles que
--    corresponde a una membresía activa propia) sin reabrir la auto-escalada.
--    set_active_center (§5) ahora escribe `roles`, y el guard trg_zz de 0105
--    bloquearía a un no-admin; se re-agrega la exención por membresía (patrón
--    del 0040, adaptado al CONJUNTO). El candado master (ambas columnas) queda.
-- -----------------------------------------------------------------------------
create or replace function public.prevent_profile_privilege_escalation()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then return new; end if;   -- alta por trigger de Auth

  if not public.is_admin() and not public.is_master() then
    -- premium jamás lo cambia un no-admin.
    if new.premium_enabled is distinct from old.premium_enabled then
      raise exception 'No autorizado: solo un administrador puede modificar premium_enabled';
    end if;
    -- Cambio de centro/roles: permitido SOLO si coincide con una membresía
    -- activa propia (el switch legítimo, que solo admin/master pueden conceder).
    if new.roles is distinct from old.roles
       or new.organization_id is distinct from old.organization_id then
      if not exists (
        select 1 from public.user_center_memberships m
        where m.profile_id = new.id
          and m.organization_id = new.organization_id
          and m.is_active = true
          and m.roles <@ new.roles and new.roles <@ m.roles
      ) then
        raise exception 'No autorizado: cambio de centro/roles sin membresía válida';
      end if;
    end if;
  end if;

  -- El rol `master` solo lo otorga o retira un master (ambas columnas).
  if not public.is_master()
     and ( ('master'::public.user_role = any(new.roles))
        <> ('master'::public.user_role = any(old.roles))
       or (new.role = 'master'::public.user_role)
        <> (old.role = 'master'::public.user_role) ) then
    raise exception 'No autorizado: solo el master puede otorgar o retirar el rol master.';
  end if;

  return new;
end; $$;
-- El trigger ya es trg_zz_prevent_profile_privilege_escalation (0105).

-- -----------------------------------------------------------------------------
-- 5. set_active_center: copia el CONJUNTO de la membresía al perfil (nunca toca
--    `role`; el espejo sync_profile_roles lo deriva). Conserva la validación de
--    membresía activa.
-- -----------------------------------------------------------------------------
create or replace function public.set_active_center(target_org uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_roles public.user_role[];
begin
  select roles into v_roles
  from public.user_center_memberships
  where profile_id = auth.uid()
    and organization_id = target_org
    and is_active = true;

  if v_roles is null then
    raise exception 'No autorizado: sin membresía activa en el centro %', target_org;
  end if;

  update public.profiles
  set organization_id = target_org,
      roles = v_roles
  where id = auth.uid();
end; $$;

-- -----------------------------------------------------------------------------
-- 6. Asientos consumidos por un centro. Licencia POR PERSONA (multi-rol al mismo
--    costo); los cuidadores NO consumen; se cuenta por persona POR CENTRO.
-- -----------------------------------------------------------------------------
create or replace function public.consumed_seats(p_org uuid)
returns integer language sql stable security definer
set search_path = public, pg_temp
as $$
  select count(*)::int
  from public.user_center_memberships m
  join public.profiles p on p.id = m.profile_id
  where m.organization_id = p_org
    and m.is_active
    and p.is_active
    and not m.seat_exempt
    and exists (select 1 from unnest(m.roles) r
                where r <> 'cuidador'::public.user_role);
$$;

comment on function public.consumed_seats(uuid) is
  'Licencias consumidas por un centro. Regla (Carlos, 31-ago-2026): la licencia es '
  'POR PERSONA y admite multiples roles al mismo costo; los cuidadores NO consumen. '
  'Se cuenta por persona POR CENTRO (el contrato es del centro).';

grant execute on function public.consumed_seats(uuid) to authenticated;
