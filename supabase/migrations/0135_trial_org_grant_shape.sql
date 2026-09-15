-- =============================================================================
-- 0135_trial_org_grant_shape.sql
-- =============================================================================
-- create_trial_organization (0125) viola ent_master_grant_shape (0132) y crear un
-- centro de prueba falla en producción con 23514: inserta SIETE filas source='master'
-- sin grant_type, reason ni is_permanent, y el CHECK los exige para source='master'.
-- Las columnas de 0132 no tienen default, así que el insert entra sin ellas.
--
-- Redefine la función desde su cuerpo VIGENTE de 0125 (no una versión anterior),
-- cambiando SOLO el insert de org_entitlements: agrega grant_type='cortesia', un reason
-- que explica el origen (prueba creada desde la consola master, con sus días) e
-- is_permanent=false — correcto porque estas filas SÍ traen current_period_end (v_end),
-- así que el CHECK pasa por la rama `current_period_end is not null`.
--
-- Nada más del cuerpo cambia: misma firma, misma autorización (solo master), mismos
-- derechos, mismo fundador opcional.
-- =============================================================================

create or replace function public.create_trial_organization(
  p_organization_name text,
  p_center_type text default 'clinica_heridas',
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
  -- Motivo de las filas master de la prueba (≥ 10 chars, cumple el CHECK).
  v_reason text := 'Prueba de ' || p_trial_days ||
                   ' días creada desde la consola del master.';
begin
  if not public.is_master() then
    raise exception 'No autorizado para crear un centro de prueba.';
  end if;

  insert into public.organizations (name, center_type, is_active, is_test)
  values (p_organization_name, p_center_type, true, p_is_test)
  returning id into v_org_id;

  -- Derechos de la PRUEBA: todo activo, con vencimiento por tiempo (current_period_end).
  -- source='master' + grant_type/reason/is_permanent para cumplir ent_master_grant_shape
  -- (0132). is_permanent=false: la caducidad la lleva current_period_end (v_end).
  insert into public.org_entitlements
    (organization_id, kind, key, quantity, status, current_period_end, source,
     grant_type, reason, is_permanent)
  values
    (v_org_id, 'plan',   'prueba',    null,             'active', v_end, 'master', 'cortesia', v_reason, false),
    (v_org_id, 'module', 'clinico',   null,             'active', v_end, 'master', 'cortesia', v_reason, false),
    (v_org_id, 'module', 'admin',     null,             'active', v_end, 'master', 'cortesia', v_reason, false),
    (v_org_id, 'module', 'insumos',   null,             'active', v_end, 'master', 'cortesia', v_reason, false),
    (v_org_id, 'module', 'comercial', null,             'active', v_end, 'master', 'cortesia', v_reason, false),
    (v_org_id, 'seat',   'clinico',   greatest(p_clinical_seats, 1),  'active', v_end, 'master', 'cortesia', v_reason, false),
    (v_org_id, 'seat',   'protocolo', greatest(p_protocolo_seats, 0), 'active', v_end, 'master', 'cortesia', v_reason, false);

  -- Fundador OPCIONAL: si se da, queda como admin.
  if p_founder_profile_id is not null then
    v_roles := case
                 when p_admin_is_clinical
                   then array['admin', 'clinico']::public.user_role[]
                 else array['admin']::public.user_role[]
               end;
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

comment on function public.create_trial_organization is
  'ÚNICO nacimiento de un centro de PRUEBA (plan:prueba, 30 días de todo, luego solo '
  'lectura por tiempo). Caller-agnóstico: fundador por parámetro, no auth.uid(). Sus '
  'filas source=master cumplen ent_master_grant_shape (0132/0135).';
