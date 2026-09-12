-- =============================================================================
-- 0125_create_trial_organization.sql — El ÚNICO lugar donde nace un centro de
-- PRUEBA (plan:prueba, 30 días de TODO, luego solo lectura). Fase de la prueba.
-- =============================================================================
-- Decisión (Carlos, 11-sep): la prueba de 30 días reemplaza al plan gratuito con
-- tope de 5 pacientes. Este RPC es la CABEZA DE CADENA — sin él, la prueba es tan
-- inerte como el cobro sin botón.
--
-- Escrito CALLER-AGNÓSTICO a propósito: el fundador se pasa por PARÁMETRO
-- (p_founder_profile_id), NO por auth.uid(). Así el mismo primitivo sirve a sus dos
-- llamantes sin cambiarlo — la consola del master (primer llamante, NO dueño) y el
-- alta pública self-service de después. Evita repetir el fork createOrganization
-- (INSERT pelón, centro inservible) vs create_organization_with_admin (acoplado a
-- auth.uid()). create_organization_with_admin (plan:gratuito) queda superado.
--
-- Autorización: master (cualquier fundador, o ninguno) O el propio usuario que se
-- da de alta a sí mismo (p_founder_profile_id = auth.uid()).
--
-- La prueba da TODO: module clinico/admin/insumos/comercial + asientos, todos con
-- current_period_end = ahora + p_trial_days y source='master'. El read-only al
-- vencer NO necesita barrido: canWriteModule ya lo hace por TIEMPO para source=
-- master (el barrido/pg_cron sería solo aseo). canReadModule sigue en true (la fila
-- existe) → el expediente se lee, no se escribe. Cantidades de asiento = parámetros
-- de producto, ajustables (Carlos).
-- =============================================================================

create or replace function public.create_trial_organization(
  p_organization_name text,
  p_center_type public.center_type default 'clinica_heridas',
  p_founder_profile_id uuid default null,
  p_admin_full_name text default null,
  p_admin_is_clinical boolean default false,
  p_trial_days int default 30,
  p_clinical_seats int default 5,
  p_protocolo_seats int default 5,
  p_is_test boolean default false
)
returns uuid language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_org_id uuid;
  v_end timestamptz := now() + make_interval(days => p_trial_days);
  v_roles public.user_role[];
begin
  -- Solo el master crea para cualquiera (o sin fundador); un usuario puede darse
  -- de alta a SÍ mismo (el alta pública). Nadie más.
  if not public.is_master()
     and (p_founder_profile_id is null or p_founder_profile_id <> auth.uid()) then
    raise exception 'No autorizado para crear un centro de prueba.';
  end if;

  insert into public.organizations (name, center_type, is_active, is_test)
  values (p_organization_name, p_center_type, true, p_is_test)
  returning id into v_org_id;

  -- Derechos de la PRUEBA: todo activo, con vencimiento por tiempo (current_period_end).
  insert into public.org_entitlements
    (organization_id, kind, key, quantity, status, current_period_end, source)
  values
    (v_org_id, 'plan',   'prueba',    null,             'active', v_end, 'master'),
    (v_org_id, 'module', 'clinico',   null,             'active', v_end, 'master'),
    (v_org_id, 'module', 'admin',     null,             'active', v_end, 'master'),
    (v_org_id, 'module', 'insumos',   null,             'active', v_end, 'master'),
    (v_org_id, 'module', 'comercial', null,             'active', v_end, 'master'),
    (v_org_id, 'seat',   'clinico',   greatest(p_clinical_seats, 1),  'active', v_end, 'master'),
    (v_org_id, 'seat',   'protocolo', greatest(p_protocolo_seats, 0), 'active', v_end, 'master');

  -- Fundador OPCIONAL: si se da, queda como admin (self-service o alta asistida por
  -- el master); si es null, el master llenará los usuarios después (admin-create-user).
  if p_founder_profile_id is not null then
    v_roles := case
                 when p_admin_is_clinical
                   then array['admin', 'clinico']::public.user_role[]
                 else array['admin']::public.user_role[]
               end;
    -- Membresía PRIMERO (el guard de profiles exige una coincidente para mover
    -- organization_id/roles).
    insert into public.user_center_memberships (profile_id, organization_id, roles, is_active)
    values (p_founder_profile_id, v_org_id, v_roles, true)
    on conflict (profile_id, organization_id)
      do update set roles = excluded.roles, is_active = true;

    update public.profiles
    set organization_id = v_org_id,
        roles = v_roles,
        full_name = coalesce(p_admin_full_name, full_name)
    where id = p_founder_profile_id;

    if p_admin_is_clinical then
      insert into public.staff (profile_id, folio, full_name, role_title, organization_id)
      values (p_founder_profile_id, '', coalesce(p_admin_full_name, 'Administrador'),
              'Administrador', v_org_id);
    end if;
  end if;

  return v_org_id;
end;
$$;

grant execute on function public.create_trial_organization(
  text, public.center_type, uuid, text, boolean, int, int, int, boolean) to authenticated;

comment on function public.create_trial_organization is
  'ÚNICO nacimiento de un centro de PRUEBA (plan:prueba, 30 días de todo, luego solo '
  'lectura por tiempo). Caller-agnóstico: fundador por parámetro, no auth.uid(). Lo '
  'llama la consola del master (primer llamante) y el alta pública después, sin cambiarlo.';
