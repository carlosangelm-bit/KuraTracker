-- =============================================================================
-- KuraTracker — SEED DEL SANDBOX (entorno de pruebas, proyecto Supabase aparte)
-- =============================================================================
-- Deja un proyecto Supabase RECIÉN migrado listo para probar funcionalidades
-- nuevas con datos 100 % sintéticos:
--
--   * 3 centros de prueba (uno por tipo), marcados organizations.is_test = true:
--       Clínica Sandbox   (clinica_heridas, con los dos premium encendidos)
--       Hospital Sandbox  (hospital)
--       Cuidadores Sandbox (cuidadores)
--   * 7 cuentas, una por rol / combinación relevante (ver tabla abajo).
--   * Personal clínico con cédula (sin cédula la nota de seguimiento no se
--     puede firmar — hallazgo de la auditoría de datos semilla del 5-sep-2026).
--   * Catálogo de conceptos de nota copiado a los 3 centros (sin él, la RLS
--     de producción deja sin chips a cualquier centro que no sea Kura+).
--   * Hospital: 3 pacientes internados con Braden alto/medio/bajo y tareas
--     preventivas; Cuidadores: 1 paciente asignado a la cuenta de cuidador.
--   * Consentimientos (privacidad + fotografía) en todos los pacientes.
--
-- Los 6 pacientes clínicos validados contra el motor (A/B/C) NO están aquí:
-- viven en seed_synthetic_patients.sql. Este archivo deja fijado
-- kt.seed_org_id para que ese seed caiga en la Clínica Sandbox — córrelo
-- DESPUÉS de éste, en la misma sesión (el workflow "Seed sandbox" lo hace).
--
-- ---------------------------------------------------------------------------
-- CÓMO CORRERLO
-- ---------------------------------------------------------------------------
-- A) GitHub → Actions → "Sandbox · seed de datos" → Run workflow (recomendado).
-- B) A mano, en el SQL Editor del proyecto SANDBOX, pegando ANTES de todo:
--
--      set kt.env = 'sandbox';
--      set kt.sandbox_password = '<clave de al menos 8 caracteres>';
--
--    y después este archivo completo. Luego, en otra query, la misma línea
--    set kt.env = 'sandbox'; + set kt.seed_org_id = 'a0000000-0000-4000-a000-000000000001';
--    + el contenido de seed_synthetic_patients.sql.
--
-- CANDADOS
--   * Se niega a correr si kt.env <> 'sandbox' (para que un copy/paste en el
--     proyecto de producción no haga nada).
--   * Es idempotente: borra sus propias filas (por id fijo / correo) y vuelve
--     a insertarlas. No toca la organización Kura+ que crea la migración 0011.
--   * Debe correr como `postgres` (SQL Editor o cadena de conexión de la BD):
--     inserta en auth.users y apaga un trigger durante la limpieza. NUNCA
--     desde el cliente con la anon key.
--
-- CUENTAS (dominio sandbox.kuratracker.mx; contraseña = kt.sandbox_password)
--   master@sandbox.kuratracker.mx        master           (plataforma, ve todo)
--   admin@sandbox.kuratracker.mx         admin            Clínica Sandbox
--   clinico@sandbox.kuratracker.mx       clinico          Clínica Sandbox
--   independiente@sandbox.kuratracker.mx admin+clinico    Clínica Sandbox
--   admin.hospital@sandbox.kuratracker.mx admin           Hospital Sandbox
--   enfermeria@sandbox.kuratracker.mx    enfermeria       Hospital Sandbox
--   cuidador → teléfono 5550001234       cuidador         Cuidadores Sandbox
--     (correo sintético 5550001234@cuidador.kuramas.com, entra con teléfono+clave)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Candados
-- -----------------------------------------------------------------------------
do $$
begin
  if coalesce(current_setting('kt.env', true), '') <> 'sandbox' then
    raise exception using
      message = 'seed_sandbox: kt.env no es ''sandbox''. Este seed solo corre en el proyecto SANDBOX.',
      hint = 'Antes del script ejecuta:  set kt.env = ''sandbox'';';
  end if;
  if length(coalesce(current_setting('kt.sandbox_password', true), '')) < 8 then
    raise exception using
      message = 'seed_sandbox: falta kt.sandbox_password (mínimo 8 caracteres).',
      hint = 'Antes del script ejecuta:  set kt.sandbox_password = ''...'';';
  end if;
  if not exists (select 1 from public.organizations) then
    raise exception 'seed_sandbox: no hay organizaciones; aplica las migraciones primero.';
  end if;
end $$;

-- Ids fijos (v4 sintéticos) para poder limpiar y re-sembrar sin duplicar.
create temp table if not exists sb on commit preserve rows as
select
  'a0000000-0000-4000-a000-000000000001'::uuid as org_clinica,
  'a0000000-0000-4000-a000-000000000002'::uuid as org_hospital,
  'a0000000-0000-4000-a000-000000000003'::uuid as org_cuidadores,
  'a0000000-0000-4000-a000-000000000011'::uuid as site_clinica,
  'a0000000-0000-4000-a000-000000000012'::uuid as site_hospital,
  'a0000000-0000-4000-a000-000000000013'::uuid as site_cuidadores,
  (select id from public.organizations order by created_at asc limit 1) as org_kura,
  current_setting('kt.sandbox_password') as pwd;

create temp table if not exists sb_emails on commit preserve rows as
select unnest(array[
  'master@sandbox.kuratracker.mx',
  'admin@sandbox.kuratracker.mx',
  'clinico@sandbox.kuratracker.mx',
  'independiente@sandbox.kuratracker.mx',
  'admin.hospital@sandbox.kuratracker.mx',
  'enfermeria@sandbox.kuratracker.mx',
  '5550001234@cuidador.kuramas.com'
]) as email;

-- -----------------------------------------------------------------------------
-- 1. Limpieza de una corrida previa (idempotencia)
-- -----------------------------------------------------------------------------
-- Las consultas finalizadas son inmutables (trigger 0097); el borrado en
-- cascada de un paciente las toca. Se apaga el candado SOLO para este bloque.
alter table public.consultations disable trigger trg_prevent_finalized_consultation_change;
delete from public.patients
 where organization_id in (select org_clinica from sb union select org_hospital from sb union select org_cuidadores from sb);
alter table public.consultations enable trigger trg_prevent_finalized_consultation_change;

-- Usuarios (cascada: profiles → memberships, module_settings, asignaciones…).
delete from auth.users where email in (select email from sb_emails);

delete from public.note_option_catalog
 where organization_id in (select org_clinica from sb union select org_hospital from sb union select org_cuidadores from sb);
delete from public.staff
 where organization_id in (select org_clinica from sb union select org_hospital from sb union select org_cuidadores from sb);
delete from public.sites
 where organization_id in (select org_clinica from sb union select org_hospital from sb union select org_cuidadores from sb);

-- -----------------------------------------------------------------------------
-- 2. Centros de prueba (is_test = true) y sedes
-- -----------------------------------------------------------------------------
insert into public.organizations (id, name, center_type, is_test, is_active,
                                  premium_insumos, premium_protocolo_kura, brand_primary_color)
select org_clinica, 'Clínica Sandbox', 'clinica_heridas', true, true, true, true, '#6A1B9A' from sb
union all
select org_hospital, 'Hospital Sandbox', 'hospital', true, true, false, false, '#1565C0' from sb
union all
select org_cuidadores, 'Cuidadores Sandbox', 'cuidadores', true, true, false, false, '#AD1457' from sb
on conflict (id) do update
  set name = excluded.name,
      center_type = excluded.center_type,
      is_test = true,
      is_active = true,
      premium_insumos = excluded.premium_insumos,
      premium_protocolo_kura = excluded.premium_protocolo_kura;

insert into public.sites (id, organization_id, name, kind, address, is_active)
select site_clinica, org_clinica, 'Clínica Sandbox · Consultorio 1', 'clinica', 'Sede sintética de pruebas', true from sb
union all
select site_hospital, org_hospital, 'Hospital Sandbox · Piso 3 Medicina Interna', 'hospital', 'Sede sintética de pruebas', true from sb
union all
select site_cuidadores, org_cuidadores, 'Cuidadores Sandbox · Domicilio', 'domicilio', 'Sede sintética de pruebas', true from sb;

-- -----------------------------------------------------------------------------
-- 3. Cuentas (auth.users + identities) → profiles → membresías → staff
-- -----------------------------------------------------------------------------
-- Misma receta que usa Supabase Auth para un usuario email+password confirmado.
-- El trigger handle_new_auth_user (0002/0011) crea el profile con el rol y la
-- organización que vienen en raw_user_meta_data; después se fija `roles`
-- (el conjunto es la autoridad; `role` lo deriva sync_profile_roles).
create or replace function pg_temp.sb_user(
  p_email text, p_full_name text, p_roles public.user_role[], p_org uuid, p_phone text default null
) returns uuid language plpgsql as $$
declare
  v_uid uuid := gen_random_uuid();
  v_pwd text := (select pwd from sb);
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    is_sso_user, is_anonymous
  ) values (
    '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
    lower(p_email), extensions.crypt(v_pwd, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'full_name', p_full_name,
      'role', public.primary_role(p_roles)::text,
      'organization_id', p_org::text
    ),
    now(), now(), '', '', '', '', false, false
  );

  insert into auth.identities (
    provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    v_uid::text, v_uid,
    jsonb_build_object('sub', v_uid::text, 'email', lower(p_email),
                       'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now()
  );

  -- Por si el trigger de Auth no existiera en este proyecto: garantiza el profile.
  insert into public.profiles (id, role, roles, full_name, email, organization_id)
  values (v_uid, public.primary_role(p_roles), p_roles, p_full_name, lower(p_email), p_org)
  on conflict (id) do update
    set roles = excluded.roles,
        full_name = excluded.full_name,
        organization_id = excluded.organization_id,
        is_active = true;

  update public.profiles set phone = p_phone where id = v_uid and p_phone is not null;

  -- Membresía en su centro. El master NO lleva membresía: el trigger
  -- trg_zz_prevent_membership_master_grant (0104) exige que quien la otorgue
  -- sea master autenticado, y desde SQL no hay sesión; is_master() se resuelve
  -- por profiles.roles, así que no la necesita.
  if not ('master'::public.user_role = any(p_roles)) then
    insert into public.user_center_memberships (profile_id, organization_id, role, roles, is_active)
    values (v_uid, p_org, public.primary_role(p_roles), p_roles, true)
    on conflict (profile_id, organization_id) do update
      set roles = excluded.roles, is_active = true;
  end if;

  return v_uid;
end $$;

-- Master: pertenece a Kura+ (la org de la 0011) y no lleva membresía adicional.
select pg_temp.sb_user('master@sandbox.kuratracker.mx', 'Master Sandbox',
  array['master']::public.user_role[], (select org_kura from sb));

-- Clínica
select pg_temp.sb_user('admin@sandbox.kuratracker.mx', 'Administrador Sandbox',
  array['admin']::public.user_role[], (select org_clinica from sb));
select pg_temp.sb_user('clinico@sandbox.kuratracker.mx', 'Dra. Clínica Sandbox',
  array['clinico']::public.user_role[], (select org_clinica from sb));
select pg_temp.sb_user('independiente@sandbox.kuratracker.mx', 'Dr. Independiente Sandbox',
  array['admin','clinico']::public.user_role[], (select org_clinica from sb));

-- Hospital
select pg_temp.sb_user('admin.hospital@sandbox.kuratracker.mx', 'Admin Hospital Sandbox',
  array['admin']::public.user_role[], (select org_hospital from sb));
select pg_temp.sb_user('enfermeria@sandbox.kuratracker.mx', 'Enf. Sandbox',
  array['enfermeria']::public.user_role[], (select org_hospital from sb));

-- Cuidadores (login por teléfono: 5550001234 + clave)
select pg_temp.sb_user('5550001234@cuidador.kuramas.com', 'Cuidador Sandbox',
  array['cuidador']::public.user_role[], (select org_cuidadores from sb), '5550001234');

-- Personal clínico (folio lo genera trg_staff_folio). Cédula en todos los que
-- firman: sin cédula la nota de seguimiento no se puede guardar.
insert into public.staff (id, profile_id, folio, full_name, role_title, cedula_profesional,
                          especialidad, primary_site_id, organization_id, is_active)
select 'a0000000-0000-4000-a000-000000000021'::uuid, p.id, '', p.full_name, 'Kuradora',
       '12345678', 'Cuidado de heridas', s.site_clinica, s.org_clinica, true
  from public.profiles p, sb s where p.email = 'clinico@sandbox.kuratracker.mx'
union all
select 'a0000000-0000-4000-a000-000000000022'::uuid, p.id, '', p.full_name, 'Administrador',
       '23456789', 'Cirugía general', s.site_clinica, s.org_clinica, true
  from public.profiles p, sb s where p.email = 'independiente@sandbox.kuratracker.mx'
union all
select 'a0000000-0000-4000-a000-000000000023'::uuid, p.id, '', p.full_name, 'Enfermería',
       '34567890', 'Enfermería', s.site_hospital, s.org_hospital, true
  from public.profiles p, sb s where p.email = 'enfermeria@sandbox.kuratracker.mx';

-- -----------------------------------------------------------------------------
-- 4. Catálogo de conceptos de nota → copia de Kura+ a los 3 centros
-- -----------------------------------------------------------------------------
insert into public.note_option_catalog (organization_id, field, label, is_active, kura_tag)
select o.org, c.field, c.label, c.is_active, c.kura_tag
  from public.note_option_catalog c
  cross join (select org_clinica as org from sb
              union all select org_hospital from sb
              union all select org_cuidadores from sb) o
 where c.organization_id = (select org_kura from sb)
on conflict (organization_id, field, label) do nothing;

-- -----------------------------------------------------------------------------
-- 5. Hospital Sandbox: 3 internados (Braden alto / medio / bajo) + tareas
-- -----------------------------------------------------------------------------
insert into public.patients (id, organization_id, primary_site_id, folio, full_name, birth_date, sex,
                             mobility, fragile_patient, background_notes, is_active)
select 'b0000000-0000-4000-a000-000000000001'::uuid, org_hospital, site_hospital, 'SBX-H-0001',
       'Esperanza Villalobos Ruiz', '1941-07-22'::date, 'F', 'encamado', true,
       'PACIENTE SINTÉTICO (sandbox). Postrada, EVC secuelar, incontinencia. Braden 9 (riesgo alto).', true
  from sb
union all
select 'b0000000-0000-4000-a000-000000000002'::uuid, org_hospital, site_hospital, 'SBX-H-0002',
       'Jorge Arriaga Mendoza', '1956-11-03'::date, 'M', 'silla_ruedas', false,
       'PACIENTE SINTÉTICO (sandbox). Post-operado de cadera, movilidad limitada. Braden 15 (riesgo medio).', true
  from sb
union all
select 'b0000000-0000-4000-a000-000000000003'::uuid, org_hospital, site_hospital, 'SBX-H-0003',
       'Lucía Ferreira Campos', '1979-02-14'::date, 'F', 'ambulatorio', false,
       'PACIENTE SINTÉTICO (sandbox). Neumonía en resolución, deambula con apoyo. Braden 19 (riesgo bajo).', true
  from sb;

insert into public.patient_admissions (organization_id, patient_id, unit, floor, area, bed, admitted_at, status, notes)
select org_hospital, 'b0000000-0000-4000-a000-000000000001'::uuid, 'Medicina Interna', '3', 'Ala Norte', '301-A', now() - interval '6 days', 'activo'::public.admission_status, 'Sintético' from sb
union all
select org_hospital, 'b0000000-0000-4000-a000-000000000002'::uuid, 'Traumatología', '3', 'Ala Norte', '305-B', now() - interval '3 days', 'activo'::public.admission_status, 'Sintético' from sb
union all
select org_hospital, 'b0000000-0000-4000-a000-000000000003'::uuid, 'Medicina Interna', '3', 'Ala Sur', '312-A', now() - interval '1 day', 'activo'::public.admission_status, 'Sintético' from sb;

insert into public.risk_assessments (organization_id, patient_id, braden_score, braden_subscores, assessed_at, assessed_by, notes)
select org_hospital, 'b0000000-0000-4000-a000-000000000001'::uuid, 9,
       '{"percepcion_sensorial":1,"humedad":1,"actividad":1,"movilidad":2,"nutricion":2,"friccion":2}'::jsonb,
       now() - interval '6 days', 'a0000000-0000-4000-a000-000000000023'::uuid, 'Valoración de ingreso (sintética)' from sb
union all
select org_hospital, 'b0000000-0000-4000-a000-000000000002'::uuid, 15,
       '{"percepcion_sensorial":3,"humedad":3,"actividad":2,"movilidad":2,"nutricion":3,"friccion":2}'::jsonb,
       now() - interval '3 days', 'a0000000-0000-4000-a000-000000000023'::uuid, 'Valoración de ingreso (sintética)' from sb
union all
select org_hospital, 'b0000000-0000-4000-a000-000000000003'::uuid, 19,
       '{"percepcion_sensorial":4,"humedad":3,"actividad":3,"movilidad":3,"nutricion":3,"friccion":3}'::jsonb,
       now() - interval '1 day', 'a0000000-0000-4000-a000-000000000023'::uuid, 'Valoración de ingreso (sintética)' from sb;

-- Tareas: una vencida (para probar el banner de vencidas), una de hoy y una futura.
insert into public.preventive_tasks (organization_id, patient_id, admission_id, rule_id, action_id, title, action_label,
                                     scheduled_at, assignee_kind, status, source, notes)
select s.org_hospital, a.patient_id, a.id, 'braden_alto', 'cambio_postural', 'Cambio postural', 'Cambio postural c/2 h',
       now() - interval '5 hours', 'staff', 'pending', 'auto', 'Sintética · vencida'
  from sb s join public.patient_admissions a on a.patient_id = 'b0000000-0000-4000-a000-000000000001'
union all
select s.org_hospital, a.patient_id, a.id, 'braden_alto', 'inspeccion_piel', 'Inspección de piel', 'Inspección de prominencias óseas',
       date_trunc('hour', now()) + interval '2 hours', 'staff', 'pending', 'auto', 'Sintética · hoy'
  from sb s join public.patient_admissions a on a.patient_id = 'b0000000-0000-4000-a000-000000000001'
union all
select s.org_hospital, a.patient_id, a.id, 'braden_medio', 'revaloracion_braden', 'Revaloración Braden', 'Revalorar Braden a 72 h',
       now() + interval '2 days', 'staff', 'pending', 'auto', 'Sintética · futura'
  from sb s join public.patient_admissions a on a.patient_id = 'b0000000-0000-4000-a000-000000000002';

-- -----------------------------------------------------------------------------
-- 6. Cuidadores Sandbox: 1 paciente domiciliario asignado al cuidador
-- -----------------------------------------------------------------------------
insert into public.patients (id, organization_id, primary_site_id, folio, full_name, birth_date, sex,
                             mobility, has_identified_caregiver, caregiver_name, caregiver_phone,
                             fragile_patient, background_notes, is_active)
select 'c0000000-0000-4000-a000-000000000001'::uuid, org_cuidadores, site_cuidadores, 'SBX-C-0001',
       'Don Aurelio Peña Salgado', '1938-05-30'::date, 'M', 'encamado', true, 'Cuidador Sandbox', '5550001234', true,
       'PACIENTE SINTÉTICO (sandbox). Domiciliario, dependiente total; LPP sacra en vigilancia por cuidador.', true
  from sb;

insert into public.caregiver_patient_assignments (organization_id, caregiver_profile_id, patient_id, assigned_by)
select s.org_cuidadores, p.id, 'c0000000-0000-4000-a000-000000000001'::uuid, null
  from sb s, public.profiles p where p.email = '5550001234@cuidador.kuramas.com'
on conflict (caregiver_profile_id, patient_id) do nothing;

insert into public.caregiver_instructions (organization_id, patient_id, instructions)
select org_cuidadores, 'c0000000-0000-4000-a000-000000000001'::uuid,
       'Cambio de posición cada 2 horas. Piel limpia y seca. Avisar si aparece enrojecimiento que no cede en 30 minutos.'
  from sb
on conflict (patient_id) do update set instructions = excluded.instructions;

insert into public.preventive_tasks (organization_id, patient_id, rule_id, action_id, title, action_label,
                                     scheduled_at, assignee_profile_id, assignee_kind, status, source, notes)
select s.org_cuidadores, 'c0000000-0000-4000-a000-000000000001'::uuid, 'domicilio', 'cambio_postural',
       'Cambio postural', 'Cambio postural', date_trunc('hour', now()) + interval '1 hour', p.id, 'cuidador', 'pending', 'auto', 'Sintética'
  from sb s, public.profiles p where p.email = '5550001234@cuidador.kuramas.com';

-- -----------------------------------------------------------------------------
-- 7. Consentimientos en todos los pacientes sembrados aquí
-- -----------------------------------------------------------------------------
insert into public.consents (patient_id, type, granted, granted_at, signed_by)
select p.id, t.type, true, now() - interval '1 day', 'Familiar responsable (sintético)'
  from public.patients p
  cross join (select unnest(array['privacidad','fotografia']::public.consent_type[]) as type) t
 where p.organization_id in (select org_hospital from sb union select org_cuidadores from sb)
on conflict (patient_id, type) do nothing;

-- -----------------------------------------------------------------------------
-- 8. Deja apuntado el seed de pacientes clínicos a la Clínica Sandbox
-- -----------------------------------------------------------------------------
-- seed_synthetic_patients.sql lee kt.seed_org_id en la MISMA sesión (y
-- siembra sus propios consentimientos).
select set_config('kt.seed_org_id', (select org_clinica::text from sb), false);
-- …y que sus 6 pacientes queden asignados también a la Dra. Clínica Sandbox
-- (un clínico solo ve a sus pacientes asignados).
select set_config('kt.seed_staff_id', 'a0000000-0000-4000-a000-000000000021', false);

drop function if exists pg_temp.sb_user(text, text, public.user_role[], uuid, text);
drop table if exists sb_emails;
drop table if exists sb;
