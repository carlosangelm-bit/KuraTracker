-- =============================================================================
-- KuraTracker - Rol "master" (administrador de plataforma)
-- =============================================================================
-- Contexto: hasta esta migracion, KuraTracker soporta multiples
-- organizaciones (centros) aisladas entre si (ver 0011), pero cada
-- organizacion administra su propia estructura (sitios, personal,
-- catalogo de nota) sin que exista ningun rol capaz de operar ESA
-- estructura a traves de TODOS los centros a la vez (p.ej. para dar
-- soporte/alta de licencias desde una consola central).
--
-- Regla de oro (no negociable, ver instrucciones del proyecto): el nuevo
-- rol "master" administra EXCLUSIVAMENTE estructura -- organizations,
-- sites, staff, note_option_catalog -- de TODAS las organizaciones. El
-- master NO obtiene NINGUN acceso a datos clinicos de pacientes ajenos
-- (patients, wounds, wound_assessments, wound_measurements,
-- consultations, wound_photos, treatment_plans, treatment_components,
-- kura_recommendations, sheehan_checkpoints, perfusion_nutrition_data,
-- audit_log, import_batches, patient_comorbidities). Ninguna policy de
-- esas tablas (todas definidas en 0003/0011) se toca en esta migracion.
-- Si en el futuro se decide dar acceso clinico al master, debe ser una
-- decision explicita y separada (nueva migracion), nunca implicita.
--
-- Gotcha de Postgres (IMPORTANTE): "alter type ... add value" no puede
-- ejecutarse en la misma transaccion que una sentencia que YA referencie
-- el nuevo valor del enum (Postgres exige que el nuevo valor del enum
-- este confirmado/visible antes de poder usarse). Por eso el ALTER TYPE
-- de abajo es la PRIMERA sentencia de este archivo, sola, sin ninguna
-- funcion/policy en el mismo archivo que la preceda y lo use. Todo lo que
-- referencia 'master' (is_master(), las policies, el trigger) va DESPUES.
-- Si tu cliente SQL envuelve todo el archivo en una sola transaccion
-- implicita y esto falla, ejecuta esta primera linea sola y el resto del
-- archivo en una segunda pasada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Enum: nuevo valor 'master' (debe ir solo, antes de cualquier uso)
-- -----------------------------------------------------------------------------
alter type public.user_role add value if not exists 'master';

-- -----------------------------------------------------------------------------
-- 1. Helper RLS: is_master() (mismo patron que is_admin(), 0002)
-- -----------------------------------------------------------------------------
create or replace function public.is_master()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'master'::public.user_role
  );
$$;

comment on function public.is_master() is
  'true si el usuario autenticado tiene role = master (administrador de '
  'plataforma). Mismo patron SECURITY DEFINER + search_path fijo que '
  'is_admin() (evita recursion de RLS y search_path hijacking). Usado '
  'para agregar, EXCLUSIVAMENTE en organizations/sites/staff/'
  'note_option_catalog, una rama adicional "or public.is_master()" SIN '
  'el filtro de organization_id -- el master ve/gestiona TODOS los '
  'centros. No se usa is_master() en ninguna policy de la cadena clinica '
  '(patients y descendientes), a proposito.';

-- -----------------------------------------------------------------------------
-- 2. RLS: ORGANIZATIONS -- master ve y gestiona TODAS; sin cambios para admin
-- -----------------------------------------------------------------------------
-- Hoy (0011) organizations solo tiene organizations_select_own (cada
-- profile ve la suya) y NINGUNA policy de escritura -- el alta de centro
-- ocurria solo via el RPC create_organization_with_admin(). El master
-- necesita poder leer/crear/editar/eliminar organizaciones directamente
-- via REST/Postgrest (sin pasar por ese RPC, que ademas promueve al
-- caller a admin de la org nueva -- flujo distinto al de master).
drop policy if exists organizations_select_own on public.organizations;
drop policy if exists organizations_master_insert on public.organizations;
drop policy if exists organizations_master_update on public.organizations;
drop policy if exists organizations_master_delete on public.organizations;

create policy organizations_select_own on public.organizations
  for select using (
    id = public.current_organization_id()
    or public.is_master()
  );
create policy organizations_master_insert on public.organizations
  for insert with check (public.is_master());
create policy organizations_master_update on public.organizations
  for update using (public.is_master());
create policy organizations_master_delete on public.organizations
  for delete using (public.is_master());

-- -----------------------------------------------------------------------------
-- 3. RLS: SITES -- agrega "or is_master()" sin filtro de organizacion
-- -----------------------------------------------------------------------------
drop policy if exists sites_select_org on public.sites;
drop policy if exists sites_admin_insert on public.sites;
drop policy if exists sites_admin_update on public.sites;
drop policy if exists sites_admin_delete on public.sites;

create policy sites_select_org on public.sites
  for select using (
    organization_id = public.current_organization_id()
    or public.is_master()
  );
create policy sites_admin_insert on public.sites
  for insert with check (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );
create policy sites_admin_update on public.sites
  for update using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );
create policy sites_admin_delete on public.sites
  for delete using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );

-- -----------------------------------------------------------------------------
-- 4. RLS: STAFF -- agrega "or is_master()" sin filtro de organizacion
-- -----------------------------------------------------------------------------
drop policy if exists staff_select_self_or_admin on public.staff;
drop policy if exists staff_admin_insert on public.staff;
drop policy if exists staff_admin_update on public.staff;
drop policy if exists staff_admin_delete on public.staff;

create policy staff_select_self_or_admin on public.staff
  for select using (
    profile_id = auth.uid()
    or (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );
create policy staff_admin_insert on public.staff
  for insert with check (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );
create policy staff_admin_update on public.staff
  for update using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );
create policy staff_admin_delete on public.staff
  for delete using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );

-- -----------------------------------------------------------------------------
-- 5. RLS: NOTE_OPTION_CATALOG -- agrega "or is_master()" sin filtro de org
-- -----------------------------------------------------------------------------
drop policy if exists note_option_catalog_select_org on public.note_option_catalog;
drop policy if exists note_option_catalog_admin_insert on public.note_option_catalog;
drop policy if exists note_option_catalog_admin_update on public.note_option_catalog;
drop policy if exists note_option_catalog_admin_delete on public.note_option_catalog;

create policy note_option_catalog_select_org on public.note_option_catalog
  for select using (
    organization_id = public.current_organization_id()
    or public.is_master()
  );
create policy note_option_catalog_admin_insert on public.note_option_catalog
  for insert with check (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );
create policy note_option_catalog_admin_update on public.note_option_catalog
  for update using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );
create policy note_option_catalog_admin_delete on public.note_option_catalog
  for delete using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );

-- -----------------------------------------------------------------------------
-- 6. Trigger prevent_profile_privilege_escalation (0006): excepcion master
-- -----------------------------------------------------------------------------
-- El master necesita poder asignar role/organization_id a OTROS profiles
-- (p.ej. promover al primer admin de un centro nuevo, mover personal de
-- organizacion). Se agrega "and not public.is_master()" a la condicion
-- que bloquea el cambio de role/premium_enabled -- el bloqueo de
-- auto-promocion de un clinico normal (el caso que este trigger existe
-- para prevenir) queda completamente intacto: un clinico sigue sin ser
-- admin ni master, is_admin() e is_master() ambos evaluan false para el,
-- por lo que la condicion "not is_admin() and not is_master()" sigue
-- siendo true y el UPDATE sigue siendo rechazado.
create or replace function public.prevent_profile_privilege_escalation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null and not public.is_admin() and not public.is_master() then
    if new.role is distinct from old.role
       or new.premium_enabled is distinct from old.premium_enabled then
      raise exception 'No autorizado: solo un administrador puede modificar role o premium_enabled';
    end if;
  end if;
  return new;
end;
$$;

-- El trigger ya existente (0006) apunta a esta funcion por nombre; al
-- recrear solo la funcion (create or replace) el trigger la usa
-- automaticamente sin necesidad de recrearlo. Se re-declara aqui de forma
-- explicita e idempotente por claridad/documentacion, sin cambiar su
-- comportamiento de disparo (BEFORE UPDATE, for each row).
drop trigger if exists trg_prevent_profile_privilege_escalation on public.profiles;
create trigger trg_prevent_profile_privilege_escalation
  before update on public.profiles
  for each row execute function public.prevent_profile_privilege_escalation();

-- =============================================================================
-- Bootstrap del primer usuario master (MANUAL, fuera de esta migracion)
-- =============================================================================
-- Este archivo NUNCA promueve a nadie a master automaticamente -- no hay
-- ningun email/credencial real en este repo. Para crear el primer master,
-- quien administre la base de datos debe ejecutar MANUALMENTE, una sola
-- vez, desde el SQL Editor de Supabase (nunca desde la app ni con la
-- anon key):
--
--   update public.profiles
--   set role = 'master'
--   where email = '<correo-del-primer-master>';
--
-- Por que funciona ese UPDATE ahi y no desde la app: el SQL Editor de
-- Supabase ejecuta con el rol de servicio de Postgres, NO como un usuario
-- autenticado via Supabase Auth -- ahi auth.uid() es NULL. La condicion
-- del trigger (arriba) es "if auth.uid() is not null and ... then
-- raise exception", por lo que cuando auth.uid() es NULL el trigger no
-- bloquea el UPDATE y el cambio de role se permite. Ese mismo UPDATE
-- ejecutado desde la app (con un usuario autenticado que no sea ya admin
-- o master) SI seria rechazado por el trigger, como debe ser.
--
-- Una vez exista al menos 1 master, ese mismo master puede promover a
-- otros usuarios a master (o admin) directamente desde la app, sin volver
-- a necesitar el SQL Editor.
-- =============================================================================
