-- =============================================================================
-- seed_prueba_fase2_user.sql — Siembra UN usuario en el centro "Prueba Fase 2"
-- (d282eab1-6f1e-40cc-b38f-a500c874d488), que no vive en seed_sandbox.sql (es un
-- artefacto de las pruebas de Stripe). Con este usuario quedan verificables tres
-- cosas de un golpe: la mitad BLOQUEADA de Insumos (module:insumos cancelado →
-- visible-y-no-pagado), la pestaña Administración de app_shell.dart:97 (admin en
-- el CONJUNTO pero role escalar distinto), y el defecto de cancelar visible desde
-- la app (plan:gratuito con derechos aún de stripe).
--
-- Se corre contra el SANDBOX como `postgres` del pooler (superusuario). Requiere
-- la contraseña de las cuentas de prueba en la variable de psql `pwd`
-- (-v pwd="$SANDBOX_USER_PASSWORD"), igual que el seed. Idempotente: por email.
--
-- CASO DE PRUEBA CLAVE: roles = {admin, clinico} pero role escalar = 'clinico'.
-- El trigger 0098 (sync_profile_roles) normalmente pone role = primary_role(roles)
-- = 'admin', así que ese estado NO se alcanza por una escritura normal — es justo
-- el desajuste que app_shell.dart:97 dejó de romper (usa el getter de CONJUNTO,
-- no el rol escalar). Se fuerza desactivando el sync SOLO para esa fila.
-- OJO: si el login re-sincroniza el perfil desde la membresía (set_active_center
-- de 0106), el role podría volver a 'admin'; verificar en la app cuál gana.
-- =============================================================================

\set ON_ERROR_STOP on

select set_config('kt.pwd', :'pwd', false);

do $$
declare
  v_org   uuid := 'd282eab1-6f1e-40cc-b38f-a500c874d488';
  v_email text := 'admin.fase2@sandbox.kuratracker.mx';
  v_name  text := 'Admin+Clínico Fase 2';
  v_pwd   text := current_setting('kt.pwd');
  v_uid   uuid;
begin
  if v_pwd is null or length(v_pwd) < 8 then
    raise exception 'Falta la contraseña (kt.pwd) o es < 8 caracteres.';
  end if;
  if not exists (select 1 from public.organizations where id = v_org) then
    raise exception 'El centro % (Prueba Fase 2) no existe en este proyecto.', v_org;
  end if;

  -- Idempotente: reusar el usuario si ya existe por email.
  select id into v_uid from auth.users where email = v_email;
  if v_uid is null then
    v_uid := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      is_sso_user, is_anonymous
    ) values (
      '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
      v_email, extensions.crypt(v_pwd, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', v_name,
                         'role', 'clinico',
                         'organization_id', v_org::text),
      now(), now(), '', '', '', '', false, false
    );
    insert into auth.identities (
      provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) values (
      v_uid::text, v_uid,
      jsonb_build_object('sub', v_uid::text, 'email', v_email,
                         'email_verified', true, 'phone_verified', false),
      'email', now(), now(), now()
    );
  end if;

  -- Perfil con el CONJUNTO {admin, clinico}. El trigger 0098 derivará role=admin;
  -- se corrige abajo forzando 'clinico'.
  insert into public.profiles (id, role, roles, full_name, email, organization_id, is_active)
  values (v_uid, 'clinico', array['admin','clinico']::public.user_role[],
          v_name, v_email, v_org, true)
  on conflict (id) do update
    set roles = excluded.roles,
        organization_id = excluded.organization_id,
        is_active = true;

  -- Membresía activa en el centro (pertenencia). El sync de 0106 derivará su
  -- role escalar = admin; para la membresía no importa (el desajuste que se
  -- prueba es el del PERFIL, que es lo que carga la sesión).
  insert into public.user_center_memberships
    (id, profile_id, organization_id, role, roles, is_active, created_at)
  values (gen_random_uuid(), v_uid, v_org, 'clinico',
          array['admin','clinico']::public.user_role[], true, now())
  on conflict (profile_id, organization_id) do update
    set roles = excluded.roles, is_active = true;
end $$;

-- Forzar role escalar = 'clinico' en el PERFIL (el desajuste de prueba). Se
-- desactiva el sync SOLO para esta escritura y se reactiva enseguida. Fuera del
-- DO para que el ENABLE quede como sentencia propia.
alter table public.profiles disable trigger trg_sync_profile_roles;
update public.profiles set role = 'clinico'
  where email = 'admin.fase2@sandbox.kuratracker.mx';
alter table public.profiles enable trigger trg_sync_profile_roles;

-- Verificación: el perfil quedó con role=clinico y roles={admin,clinico}.
select p.email, p.role, p.roles, p.is_active, p.organization_id
from public.profiles p
where p.email = 'admin.fase2@sandbox.kuratracker.mx';
