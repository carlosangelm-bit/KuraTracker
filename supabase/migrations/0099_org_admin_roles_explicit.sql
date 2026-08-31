-- =============================================================================
-- 0099_org_admin_roles_explicit.sql — Alta de centro: el admin nace en {admin}
-- =============================================================================
-- Hallazgo (punto 7): create_organization_with_admin (0011) hacía
--   update public.profiles set role = 'admin' ...
-- lo que cae en el ATAJO DE COMPATIBILIDAD del trigger sync_profile_roles
-- (0098): al cambiar `role` a 'admin', el trigger reescribe
-- roles := {admin, clinico}. Es decir, el administrador de TODO centro cliente
-- nuevo nacía con rol clínico (escritura clínica a nivel de RLS) sin que nadie
-- lo decidiera. Inofensivo hoy (una sola org, todas las cuentas son nuestras),
-- pero un centro cliente onboardeado por esta vía expondría a una persona
-- administrativa con permisos clínicos.
--
-- Corrección: el RPC escribe `roles` EXPLÍCITO (autoridad); el trigger deriva el
-- espejo `role`. Por defecto {admin} (centro con equipo: el admin no atiende
-- pacientes). El parámetro p_admin_is_clinical=true produce {admin, clinico}
-- para el profesional independiente que es su propio centro y sí atiende — la
-- pregunta que el onboarding debe hacer explícita, no heredar del atajo.
--
-- La fila de `staff` solo se crea para el caso clínico: un {admin}-only no
-- diagnostica (canDiagnose=false), así que no necesita staff; si alguna vez lo
-- necesitara, ensureAdminStaffId (app) se la aprovisiona al vuelo. Esto también
-- evita ensuciar la lista de personal con administrativos que no atienden.
--
-- NO se toca el `case` de compat del trigger todavía (0098): se retira cuando
-- NINGUNA vía de alta dependa de él (admin-create-user ya escribe roles; esta es
-- la otra vía). Mientras exista un writer legacy, quitarlo rompe altas.
--
-- La firma cambia (se agrega un 3er parámetro con default), así que se DROP+CREATE:
-- mantener la firma de 2 args coexistiendo haría ambigua la llamada con 2 args.
-- =============================================================================

drop function if exists public.create_organization_with_admin(text, text);

create or replace function public.create_organization_with_admin(
  p_organization_name text,
  p_admin_full_name text,
  p_admin_is_clinical boolean default false
)
returns uuid language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_org_id uuid;
  v_staff_id uuid;
begin
  if auth.uid() is null then
    raise exception 'No autenticado';
  end if;

  insert into public.organizations (name) values (p_organization_name)
  returning id into v_org_id;

  -- Se escribe `roles` (el conjunto, autoridad). NO se toca `role`: el trigger
  -- sync_profile_roles deriva el espejo desde roles. Así se evita el atajo de
  -- compatibilidad que daría clinico al admin sin pedirlo.
  update public.profiles
  set organization_id = v_org_id,
      roles = case
                when p_admin_is_clinical
                  then array['admin', 'clinico']::public.user_role[]
                else array['admin']::public.user_role[]
              end,
      full_name = coalesce(p_admin_full_name, full_name)
  where id = auth.uid();

  -- staff solo para el admin clínico (el que atiende). Un {admin}-only no lo
  -- necesita (no diagnostica) y ensureAdminStaffId lo cubriría al vuelo.
  if p_admin_is_clinical then
    insert into public.staff (profile_id, folio, full_name, role_title, organization_id)
    values (auth.uid(), '', coalesce(p_admin_full_name, 'Administrador'), 'Administrador', v_org_id)
    returning id into v_staff_id;
  end if;

  return v_org_id;
end;
$$;

comment on function public.create_organization_with_admin(text, text, boolean) is
  'Alta de un centro nuevo (licencia individual): crea la organizacion y promueve '
  'al profile autenticado a admin de esa organizacion escribiendo roles EXPLICITO '
  '(punto 7): {admin} por defecto (centro con equipo, el admin no atiende) o '
  '{admin,clinico} si p_admin_is_clinical (profesional independiente que atiende). '
  'El espejo `role` lo deriva el trigger sync_profile_roles. La fila de staff solo '
  'se crea en el caso clinico.';
