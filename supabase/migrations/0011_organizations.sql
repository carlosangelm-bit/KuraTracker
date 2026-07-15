-- =============================================================================
-- KuraTracker - Modelo Centro (organizacion) -> Sitios -> Personal
-- =============================================================================
-- Contexto (instruccion "Modelo Centro -> Sitios -> Personal" + catalogos
-- CSV): hasta esta migracion, KuraTracker era de facto mono-tenant: no
-- existia ningun concepto de "centro/organizacion" en el esquema, por lo
-- que cualquier admin veia TODOS los sitios/personal/pacientes de la base,
-- sin ningun limite. Esta migracion introduce el tenant "organizations" y
-- aisla por organizacion las tablas que antes eran globales:
--   organizations  (NUEVA) -> el centro (p.ej. "Kura+").
--   sites          -> ahora pertenece a 1 organizacion (organization_id).
--   profiles       -> el USUARIO logueado pertenece a 1 organizacion
--                      (organization_id). Es la fuente de verdad para
--                      current_organization_id().
--   staff          -> tambien lleva su propio organization_id (no se
--                      infiere solo via profile_id) para soportar personal
--                      administrativo SIN cuenta de acceso (profile_id
--                      NULL), que de otra forma no tendria organizacion
--                      resoluble.
--   note_option_catalog -> catalogo de conceptos de nota de seguimiento,
--                      ahora configurable por CENTRO (antes era global a
--                      toda la base).
--   patients       -> CRITICO: el aislamiento multi-tenant real ocurre
--                      aqui. Antes, la policy patients_select le daba a
--                      CUALQUIER admin (de cualquier organizacion) SELECT
--                      de TODOS los pacientes de la base -- un bug de
--                      aislamiento grave en un escenario multi-centro. Se
--                      agrega patients.organization_id y se reescribe la
--                      policy: un admin ve/edita solo pacientes de SU
--                      organizacion; un clinico sigue viendo solo los que
--                      tiene asignados (staff_patient_assignments), y esa
--                      asignacion ya esta transitivamente acotada a la
--                      organizacion porque tanto staff como patients ahora
--                      llevan organization_id verificado.
--                      wounds/wound_assessments/wound_measurements/
--                      perfusion_nutrition_data/wound_photos/
--                      treatment_plans/treatment_components/
--                      kura_recommendations/sheehan_checkpoints NO
--                      necesitan columna organization_id propia: heredan
--                      el aislamiento por FK transitiva hacia patients (ya
--                      es como estaban escritas sus policies en 0003,
--                      "where w.patient_id = patients.id" etc.) -- basta
--                      con que la policy de patients quede correctamente
--                      acotada por organizacion para que TODA la cadena
--                      quede aislada, sin tocar esas 9 tablas.
--
-- Helper nuevo: current_organization_id() (mismo patron SECURITY DEFINER +
-- search_path fijo que is_admin()/current_staff_id(), ver
-- 0002_triggers_and_functions.sql), resuelve la organizacion del profile
-- autenticado. admin y clinico usan el MISMO helper (no hay 2 formas de
-- resolver la organizacion): así una fila de staff sin profile_id vinculado
-- (personal administrativo) sigue existiendo dentro de la organizacion
-- correcta aunque nadie la use para iniciar sesion.
--
-- Backfill: se crea una organizacion "Kura+" (unica existente hoy en
-- produccion/demo) y se le asignan TODAS las filas existentes de
-- sites/profiles/staff/note_option_catalog/patients. No se pierde ningun
-- dato ni relacion.
--
-- staff.primary_site_id: sigue existiendo sin cambios de esquema. Su
-- semantica pasa a ser EXPLICITAMENTE "default opcional, no limite": el
-- personal de un centro puede operar (crear consultas) en cualquier sitio
-- de su organizacion, elegido libremente en el formulario de "Nueva
-- consulta" (ya era el comportamiento de la UI antes de esta migracion,
-- ver consultation_hub_screen.dart / patient_form_screen.dart /
-- follow_up_capture_screen.dart -- ninguno de esos filtraba por
-- primary_site_id, solo lo usaban como valor por defecto). No se agrega
-- ninguna restriccion de RLS basada en primary_site_id.
--
-- RLS por organizacion (regla transversal obligatoria): SELECT/INSERT/
-- UPDATE/DELETE en sites/note_option_catalog/patients quedan acotados a
-- organization_id = current_organization_id(). Sin INSERT de cliente a
-- audit_log: ninguna de las tablas tocadas aqui esta en el alcance de
-- audit_trigger_fn (organizations/sites/note_option_catalog no son datos
-- clinicos de paciente; patients SI esta auditada, pero via el trigger ya
-- existente de 0002, no cambia nada de eso aqui).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. TABLA ORGANIZATIONS (el centro)
-- -----------------------------------------------------------------------------

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.organizations is
  'Centro/clinica (tenant). Cada organizacion tiene 1->N sitios y su '
  'propio personal, pacientes y catalogo de conceptos de nota de '
  'seguimiento. El personal puede operar en TODOS los sitios de su '
  'organizacion (primary_site_id es solo un default, no un limite).';

-- Backfill: unica organizacion existente hasta ahora.
insert into public.organizations (id, name)
select gen_random_uuid(), 'Kura+'
where not exists (select 1 from public.organizations);

-- -----------------------------------------------------------------------------
-- 2. organization_id en sites / profiles / staff / note_option_catalog / patients
-- -----------------------------------------------------------------------------

alter table public.sites
  add column if not exists organization_id uuid references public.organizations(id);
alter table public.profiles
  add column if not exists organization_id uuid references public.organizations(id);
alter table public.staff
  add column if not exists organization_id uuid references public.organizations(id);
alter table public.note_option_catalog
  add column if not exists organization_id uuid references public.organizations(id);
alter table public.patients
  add column if not exists organization_id uuid references public.organizations(id);

-- Backfill de filas existentes hacia la (unica) organizacion creada arriba.
do $$
declare
  v_org_id uuid;
begin
  select id into v_org_id from public.organizations order by created_at asc limit 1;

  update public.sites set organization_id = v_org_id where organization_id is null;
  update public.profiles set organization_id = v_org_id where organization_id is null;
  update public.staff set organization_id = v_org_id where organization_id is null;
  update public.note_option_catalog set organization_id = v_org_id where organization_id is null;
  update public.patients set organization_id = v_org_id where organization_id is null;
end $$;

alter table public.sites alter column organization_id set not null;
alter table public.profiles alter column organization_id set not null;
alter table public.staff alter column organization_id set not null;
alter table public.note_option_catalog alter column organization_id set not null;
alter table public.patients alter column organization_id set not null;

create index if not exists idx_sites_organization_id on public.sites(organization_id);
create index if not exists idx_profiles_organization_id on public.profiles(organization_id);
create index if not exists idx_staff_organization_id on public.staff(organization_id);
create index if not exists idx_note_option_catalog_organization_id on public.note_option_catalog(organization_id);
create index if not exists idx_patients_organization_id on public.patients(organization_id);

comment on column public.staff.organization_id is
  'Organizacion (centro) a la que pertenece este registro de personal. '
  'Se guarda explicitamente (no solo via profile_id) porque el personal '
  'administrativo puede no tener cuenta de acceso vinculada '
  '(profile_id NULL) y aun asi debe quedar resoluble a una organizacion.';
comment on column public.patients.organization_id is
  'Organizacion (centro) due~a del expediente. Aisla pacientes entre '
  'centros distintos: un admin ve/edita solo los pacientes de SU '
  'organizacion (nunca todos los de la base), ver policies mas abajo.';

-- -----------------------------------------------------------------------------
-- 3. handle_new_auth_user(): asigna organization_id al crear el profile
-- -----------------------------------------------------------------------------
-- Un usuario nuevo se registra siempre dentro de una organizacion (hoy,
-- unica: Kura+). raw_user_meta_data.organization_id permite en el futuro
-- soportar altas de licencia individual con su propio centro nuevo (ver
-- create_organization_with_admin mas abajo); si no viene, se usa la
-- organizacion existente mas antigua como default (comportamiento actual
-- de piloto mono-organizacion).
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_org_id uuid;
begin
  v_org_id := (new.raw_user_meta_data->>'organization_id')::uuid;
  if v_org_id is null then
    select id into v_org_id from public.organizations order by created_at asc limit 1;
  end if;

  insert into public.profiles (id, role, full_name, email, organization_id)
  values (
    new.id,
    coalesce((new.raw_user_meta_data->>'role')::public.user_role, 'clinico'::public.user_role),
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    v_org_id
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Helper RLS: current_organization_id()
-- -----------------------------------------------------------------------------
create or replace function public.current_organization_id()
returns uuid language sql stable security definer
set search_path = public, pg_temp
as $$
  select organization_id from public.profiles where id = auth.uid();
$$;

comment on function public.current_organization_id() is
  'Organizacion (centro) del usuario autenticado, resuelta via '
  'profiles.organization_id. Usada por las policies RLS de '
  'sites/note_option_catalog/patients para acotar SELECT/escritura al '
  'centro del usuario, en vez de a toda la base.';

-- -----------------------------------------------------------------------------
-- 5. Fix admin-clinico (licencia individual): alta de centro + admin propio
-- -----------------------------------------------------------------------------
-- Bug corregido: un admin de licencia individual (sin fila propia en
-- `staff`) no podia crear consultas porque createConsultation/
-- current_staff_id() requieren un staff_id resoluble, y ConsultationHub/
-- FollowUpCapture bloqueaban el flujo si session.user.staffId era null. La
-- correccion de UI/repo (ver DataRepository.createConsultation +
-- pantallas) ahora permite crear la consulta si el usuario es admin
-- (aun sin staffId), pero para que esa consulta y sus datos queden
-- correctamente atribuidos y visibles bajo RLS conviene que TODO admin
-- tenga tambien su propio registro de staff. Este RPC crea, en una sola
-- transaccion, la organizacion + el profile admin + su staff, para el
-- flujo de alta de un centro/licencia nueva. Se expone como RPC
-- (security definer) porque profiles/staff/organizations no permiten
-- INSERT libre por RLS a un usuario recien autenticado sin organizacion
-- aun asignada.
create or replace function public.create_organization_with_admin(
  p_organization_name text,
  p_admin_full_name text
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

  update public.profiles
  set organization_id = v_org_id,
      role = 'admin'::public.user_role,
      full_name = coalesce(p_admin_full_name, full_name)
  where id = auth.uid();

  insert into public.staff (profile_id, folio, full_name, role_title, organization_id)
  values (auth.uid(), '', coalesce(p_admin_full_name, 'Administrador'), 'Administrador', v_org_id)
  returning id into v_staff_id;

  return v_org_id;
end;
$$;

comment on function public.create_organization_with_admin(text, text) is
  'Alta de un centro nuevo (licencia individual): crea la organizacion, '
  'promueve el profile autenticado a admin de esa organizacion y crea su '
  'fila de staff (para que pueda crear consultas como cualquier otro '
  'personal). Pensado para el flujo de auto-registro de un admin nuevo '
  'sin organizacion previa.';

-- -----------------------------------------------------------------------------
-- 6. RLS: SITES (ahora por organizacion, no global)
-- -----------------------------------------------------------------------------
drop policy if exists sites_select_all on public.sites;
drop policy if exists sites_admin_write on public.sites;
drop policy if exists sites_admin_update on public.sites;
drop policy if exists sites_admin_delete on public.sites;

create policy sites_select_org on public.sites
  for select using (organization_id = public.current_organization_id());
create policy sites_admin_insert on public.sites
  for insert with check (public.is_admin() and organization_id = public.current_organization_id());
create policy sites_admin_update on public.sites
  for update using (public.is_admin() and organization_id = public.current_organization_id());
create policy sites_admin_delete on public.sites
  for delete using (public.is_admin() and organization_id = public.current_organization_id());

-- -----------------------------------------------------------------------------
-- 7. RLS: STAFF (agrega verificacion de organizacion a las policies 0003)
-- -----------------------------------------------------------------------------
drop policy if exists staff_select_self_or_admin on public.staff;
drop policy if exists staff_admin_insert on public.staff;
drop policy if exists staff_admin_update on public.staff;
drop policy if exists staff_admin_delete on public.staff;

create policy staff_select_self_or_admin on public.staff
  for select using (
    profile_id = auth.uid()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );
create policy staff_admin_insert on public.staff
  for insert with check (public.is_admin() and organization_id = public.current_organization_id());
create policy staff_admin_update on public.staff
  for update using (public.is_admin() and organization_id = public.current_organization_id());
create policy staff_admin_delete on public.staff
  for delete using (public.is_admin() and organization_id = public.current_organization_id());

-- -----------------------------------------------------------------------------
-- 8. RLS: NOTE_OPTION_CATALOG (ahora por organizacion, no global)
-- -----------------------------------------------------------------------------
drop policy if exists note_option_catalog_select_all on public.note_option_catalog;
drop policy if exists note_option_catalog_admin_insert on public.note_option_catalog;
drop policy if exists note_option_catalog_admin_update on public.note_option_catalog;
drop policy if exists note_option_catalog_admin_delete on public.note_option_catalog;

create policy note_option_catalog_select_org on public.note_option_catalog
  for select using (organization_id = public.current_organization_id());
create policy note_option_catalog_admin_insert on public.note_option_catalog
  for insert with check (public.is_admin() and organization_id = public.current_organization_id());
create policy note_option_catalog_admin_update on public.note_option_catalog
  for update using (public.is_admin() and organization_id = public.current_organization_id());
create policy note_option_catalog_admin_delete on public.note_option_catalog
  for delete using (public.is_admin() and organization_id = public.current_organization_id());

-- Restriccion de unicidad (field, label) pasa a ser por organizacion (dos
-- centros distintos pueden tener un concepto con el mismo texto).
alter table public.note_option_catalog
  drop constraint if exists note_option_catalog_field_label_unique;
alter table public.note_option_catalog
  add constraint note_option_catalog_field_label_org_unique unique (organization_id, field, label);

-- -----------------------------------------------------------------------------
-- 9. RLS: PATIENTS (CRITICO) -- admin ve solo su organizacion, no toda la base
-- -----------------------------------------------------------------------------
-- Antes (0003): patients_select daba public.is_admin() -> SELECT de TODOS
-- los pacientes de la base, sin distincion de organizacion. Se reemplaza
-- por una condicion que exige ADEMAS organization_id = current_organization_id().
-- El resto de la cadena (wounds, consultations, measurements, etc.) hereda
-- este aislamiento transitivamente via join a patients (sus policies ya
-- filtran por patients.id + staff_patient_assignments, sin cambios).
drop policy if exists patients_select on public.patients;
drop policy if exists patients_insert on public.patients;
drop policy if exists patients_update on public.patients;
drop policy if exists patients_admin_delete on public.patients;

create policy patients_select on public.patients
  for select using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patients.id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy patients_insert on public.patients
  for insert with check (
    organization_id = public.current_organization_id()
    and (public.is_admin() or public.current_staff_id() is not null)
  );
create policy patients_update on public.patients
  for update using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or exists (
      select 1 from public.staff_patient_assignments spa
      where spa.patient_id = patients.id
        and spa.staff_id = public.current_staff_id()
    )
  );
create policy patients_admin_delete on public.patients
  for delete using (public.is_admin() and organization_id = public.current_organization_id());

-- -----------------------------------------------------------------------------
-- 10. RLS: ORGANIZATIONS (lectura de la propia; sin escritura de cliente)
-- -----------------------------------------------------------------------------
alter table public.organizations enable row level security;

create policy organizations_select_own on public.organizations
  for select using (id = public.current_organization_id());

-- No se agregan policies de insert/update/delete: el alta de organizacion
-- se hace exclusivamente via el RPC create_organization_with_admin()
-- (security definer), nunca por INSERT directo del cliente a la tabla.
