-- =============================================================================
-- 0111_prevent_org_without_clinico.sql
-- (numerada 0111 para no chocar con 0108-0110 del motor de visión que ya viven
--  en staging; en main el hueco 0108-0110 se llena cuando esa feature llegue.)
-- =============================================================================
-- Guardia "último clínico del centro" (huecos #2 y #3, 8-sep-2026 — decisión de
-- Carlos: BLOQUEAR). Un centro no debe quedarse sin ningún clínico EFECTIVO: sin
-- él, nadie puede definir planes de cuidado. La app ya lo valida en cliente
-- (setUserRoles / setUserActive); esto lo hace cumplir también del lado servidor,
-- para el acceso directo por PostgREST.
--
-- Clínico EFECTIVO = membresía ACTIVA con 'clinico' Y perfil ACTIVO. Un perfil
-- inactivo no puede iniciar sesión, así que su rol clínico no cuenta. Por eso la
-- invariante tiene DOS puertas y aquí se cierran ambas con una sola función:
--   1) user_center_memberships: quitar 'clinico' de la membresía, desactivarla o
--      borrarla (trigger de esta tabla).
--   2) profiles.is_active: desactivar el perfil lo saca de TODOS sus centros
--      (trigger de profiles) — la puerta MÁS probable (dar de baja a quien se va).
--
-- Los triggers corren como `trg_zz_*` para dispararse DESPUÉS del sync role↔roles
-- de 0106 (Postgres ordena los BEFORE por nombre) y validar el estado FINAL. La
-- función es SECURITY DEFINER con `set search_path = public` para contar todas las
-- membresías/perfiles del centro sin depender de la RLS del que llama. Compara por
-- `roles::text[]` para no atarse al literal del enum.
-- =============================================================================

-- ¿Queda algún clínico EFECTIVO en el centro además de p_exclude?
create or replace function public.org_has_other_effective_clinico(
  p_org uuid, p_exclude uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_center_memberships m
    join public.profiles pr on pr.id = m.profile_id
    where m.organization_id = p_org
      and m.profile_id <> p_exclude
      and m.is_active = true
      and pr.is_active = true
      and 'clinico' = any(m.roles::text[])
  );
$$;

-- Puerta 1: la membresía (quitar rol / desactivar / borrar).
create or replace function public.prevent_org_without_clinico()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- ¿La fila afectada aportaba 'clinico' y estaba ACTIVA antes? Si no, no puede
  -- estar quitando el último clínico; nada que validar.
  if not (old.is_active and ('clinico' = any(old.roles::text[]))) then
    return coalesce(new, old);
  end if;

  -- UPDATE que conserva la membresía activa y con 'clinico': no se pierde nada.
  if tg_op = 'UPDATE'
     and new.is_active
     and ('clinico' = any(new.roles::text[])) then
    return new;
  end if;

  if public.org_has_other_effective_clinico(old.organization_id, old.profile_id) then
    return coalesce(new, old);
  end if;

  raise exception 'No autorizado: el centro se quedaría sin personal sanitario (nadie podría definir planes de cuidado).';
end;
$$;

drop trigger if exists trg_zz_prevent_org_without_clinico
  on public.user_center_memberships;
create trigger trg_zz_prevent_org_without_clinico
  before update or delete on public.user_center_memberships
  for each row execute function public.prevent_org_without_clinico();

-- Puerta 2: el perfil (desactivarlo lo saca de TODOS sus centros). Si en ALGÚN
-- centro donde tiene membresía clínica activa era el último clínico efectivo, se
-- rechaza.
create or replace function public.prevent_profile_deactivation_without_clinico()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
begin
  -- Solo aplica al DESACTIVAR un perfil que estaba activo.
  if not (old.is_active and not new.is_active) then
    return new;
  end if;
  for v_org in
    select m.organization_id
    from public.user_center_memberships m
    where m.profile_id = old.id
      and m.is_active = true
      and 'clinico' = any(m.roles::text[])
  loop
    if not public.org_has_other_effective_clinico(v_org, old.id) then
      raise exception 'No autorizado: al desactivar a este usuario el centro se quedaría sin personal sanitario (nadie podría definir planes de cuidado).';
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_zz_prevent_profile_deactivation_without_clinico
  on public.profiles;
create trigger trg_zz_prevent_profile_deactivation_without_clinico
  before update on public.profiles
  for each row execute function public.prevent_profile_deactivation_without_clinico();
