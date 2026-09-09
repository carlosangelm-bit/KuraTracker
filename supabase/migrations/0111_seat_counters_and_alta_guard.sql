-- =============================================================================
-- 0111_seat_counters_and_alta_guard.sql — Dos contadores de asiento + tope en el
-- alta del usuario (Fase 1, §6).
-- =============================================================================
-- consumed_seats() (0106) contaba a toda persona activa no-cuidadora en un solo
-- balde. El modelo de licencia distingue ASIENTO CLÍNICO de CUPO ADMINISTRATIVO:
--   · consumed_clinical_seats(org): personas con ALGÚN rol clínico (clinico,
--       enfermeria), no exentas. Multi-rol = un asiento.
--   · consumed_admin_slots(org): personas cuyo conjunto de roles es SOLO
--       administrativo (admin, sin ningún rol clínico), no exentas.
-- Reglas (Carlos, ya decididas): quien tiene rol clínico consume asiento CLÍNICO
-- y NO ocupa cupo admin aunque además sea admin; los cuidadores no consumen;
-- module:admin incluye 3 cupos admin, del 4º en adelante consume asiento clínico;
-- profesional único (clínico+admin) = 1 asiento clínico y NO requiere module:admin.
--
-- consumed_seats() (0106) se CONSERVA: lo usó el backfill 0109 (seat:clinico) y no
-- se reescribe una función vigente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Capacidad clínica POR PERFIL (una sola definición de "quién es clínico").
--    Réplica de AppUser.canDiagnose: 'clinico' en el conjunto efectivo, con el
--    relleno admin→{admin,clinico} cuando roles viene vacío. Los contadores de
--    asiento miden por ESTO (perfil), no por la membresía, para que la gerencia
--    clínica de hospital consuma su asiento clínico y no un cupo administrativo
--    gratis (falla SILENCIOSA: nadie la ve).
--
--    IMPORTANTE: este cuerpo es IDÉNTICO al de fix/prevent-org-without-clinico-0108
--    (0112_capable_clinico_by_profile) y ambos usan create-or-replace, así que el
--    ORDEN de aplicación no importa: la que corra al final escribe el mismo cuerpo.
--    Si se cambia una, cambiar la otra igual. (Decisión 9-sep: la función de 10
--    líneas viaja con licencia sin merge a main; la guardia server-side —triggers,
--    falla VISIBLE que el master arregla en 30 s— sale de la ruta crítica.)
create or replace function public.profile_can_define_plans(
  p_roles public.user_role[], p_role public.user_role
) returns boolean
language sql
immutable
as $$
  select case
    when coalesce(cardinality(p_roles), 0) > 0
      then 'clinico' = any(p_roles::text[])
    else p_role::text in ('admin', 'clinico')
  end;
$$;

-- -----------------------------------------------------------------------------
-- 1. Contadores (miden por capacidad de PERFIL, no por membresía).
-- -----------------------------------------------------------------------------
create or replace function public.consumed_clinical_seats(p_org uuid)
returns integer language sql stable security definer
set search_path = public, pg_temp
as $$
  select count(*)::int
  from public.user_center_memberships m
  join public.profiles p on p.id = m.profile_id
  where m.organization_id = p_org
    and m.is_active and p.is_active and not m.seat_exempt
    and public.profile_can_define_plans(p.roles, p.role);
$$;

comment on function public.consumed_clinical_seats(uuid) is
  'Asientos CLÍNICOS consumidos: personas con algún rol clínico (clinico/enfermeria), '
  'no exentas, activas, por centro. Multi-rol = un asiento.';

create or replace function public.consumed_admin_slots(p_org uuid)
returns integer language sql stable security definer
set search_path = public, pg_temp
as $$
  select count(*)::int
  from public.user_center_memberships m
  join public.profiles p on p.id = m.profile_id
  where m.organization_id = p_org
    and m.is_active and p.is_active and not m.seat_exempt
    and not public.profile_can_define_plans(p.roles, p.role)
    and ('admin'::public.user_role = any(p.roles));
$$;

comment on function public.consumed_admin_slots(uuid) is
  'Cupos ADMINISTRATIVOS consumidos: personas cuyo conjunto de roles es SOLO '
  'administrativo (admin, sin rol clínico), no exentas, activas. Quien tiene rol '
  'clínico NO ocupa cupo admin aunque sea admin.';

grant execute on function public.consumed_clinical_seats(uuid) to authenticated;
grant execute on function public.consumed_admin_slots(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Tope en el alta. Se aplica ANTES de crear (no en la factura). La comparten
--    admin-create-user (Edge, service_role, vía RPC) y create_organization_with_admin.
--    Lanza una excepción accionable (prefijo SEAT_*) que la pantalla convierte en
--    la oferta de comprar. No escribe nada: solo valida.
-- -----------------------------------------------------------------------------
create or replace function public.assert_seat_available(p_org uuid, p_roles public.user_role[])
returns void language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_has_clinical boolean := exists (select 1 from unnest(p_roles) r
                              where r in ('clinico'::public.user_role, 'enfermeria'::public.user_role));
  v_has_admin boolean := ('admin'::public.user_role = any(p_roles));
  v_member_count int;
  v_has_admin_module boolean;
  v_clinical_cap int;
  v_clinical_used int;
  v_admin_used int;
begin
  -- Cuidador puro (sin rol clínico ni admin) no consume nada.
  if not v_has_clinical and not v_has_admin then
    return;
  end if;

  select count(*) into v_member_count
  from public.user_center_memberships m
  join public.profiles p on p.id = m.profile_id
  where m.organization_id = p_org and m.is_active and p.is_active;

  v_has_admin_module := exists (
    select 1 from public.org_entitlements e
    where e.organization_id = p_org and e.kind = 'module' and e.key = 'admin'
      and e.status = 'active');

  -- module:admin obligatorio a partir del SEGUNDO usuario (el profesional único no
  -- lo necesita). Si ya hay al menos un miembro y no hay module:admin, se rechaza.
  if v_member_count >= 1 and not v_has_admin_module then
    raise exception 'SEAT_REQUIRES_ADMIN_MODULE: el centro necesita el módulo Administración para agregar un segundo usuario.';
  end if;

  select coalesce(max(quantity), 0) into v_clinical_cap
  from public.org_entitlements e
  where e.organization_id = p_org and e.kind = 'seat' and e.key = 'clinico'
    and e.status = 'active';

  -- Con rol clínico: consume asiento clínico.
  if v_has_clinical then
    v_clinical_used := public.consumed_clinical_seats(p_org);
    if v_clinical_used + 1 > v_clinical_cap then
      raise exception 'SEAT_NO_CLINICAL: no hay asientos clínicos disponibles (% de % en uso).', v_clinical_used, v_clinical_cap;
    end if;
    return;
  end if;

  -- Solo administrativo: entra en cupo admin (3 con module:admin); del 4º en
  -- adelante, o sin module:admin, consume un asiento clínico.
  v_admin_used := public.consumed_admin_slots(p_org);
  if v_has_admin_module and v_admin_used < 3 then
    return;
  end if;
  v_clinical_used := public.consumed_clinical_seats(p_org);
  if v_clinical_used + 1 > v_clinical_cap then
    raise exception 'SEAT_NO_CLINICAL: no hay asientos clínicos disponibles (% de % en uso).', v_clinical_used, v_clinical_cap;
  end if;
end;
$$;

grant execute on function public.assert_seat_available(uuid, public.user_role[]) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. create_organization_with_admin: al crear un centro de autoservicio, otorgar
--    los derechos BASE para que el fundador (profesional único) funcione. Sin
--    esto, el tope del §6 rechazaría al fundador (centro nuevo = sin derechos =
--    sin asientos). Base = plan gratuito + module:clinico + seat:clinico(1).
--
--    NOTA / SUPUESTO DE FASE 1: qué derechos recibe un centro NUEVO es materia de
--    plan/registro (fases 2-5). Aquí se otorga el mínimo para no romper el alta de
--    autoservicio (1 asiento clínico, sin module:admin: agregar un 2º usuario exige
--    comprarlo). Ajustable cuando se defina el plan gratuito. (Marcado para Carlos.)
--
--    Reproduce el resto de 0106 sin cambios; solo agrega el bloque de derechos.
-- -----------------------------------------------------------------------------
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
  v_roles public.user_role[];
begin
  if auth.uid() is null then
    raise exception 'No autenticado';
  end if;

  v_roles := case
               when p_admin_is_clinical
                 then array['admin', 'clinico']::public.user_role[]
               else array['admin']::public.user_role[]
             end;

  insert into public.organizations (name) values (p_organization_name)
  returning id into v_org_id;

  -- Derechos base del centro nuevo (ver NOTA arriba). Antes de la membresía, para
  -- que el guard de asientos (si se invocara) ya encuentre el asiento del fundador.
  insert into public.org_entitlements (organization_id, kind, key, quantity, status, source)
  values
    (v_org_id, 'plan',   'gratuito', null, 'active', 'master'),
    (v_org_id, 'module', 'clinico',  null, 'active', 'master'),
    (v_org_id, 'seat',   'clinico',  1,    'active', 'master');

  -- Membresía PRIMERO (el guard de profiles exige una coincidente para el cambio
  -- de organization_id/roles, que ahora aplica también a admins).
  insert into public.user_center_memberships (profile_id, organization_id, roles, is_active)
  values (auth.uid(), v_org_id, v_roles, true)
  on conflict (profile_id, organization_id)
    do update set roles = excluded.roles, is_active = true;

  update public.profiles
  set organization_id = v_org_id,
      roles = v_roles,
      full_name = coalesce(p_admin_full_name, full_name)
  where id = auth.uid();

  if p_admin_is_clinical then
    insert into public.staff (profile_id, folio, full_name, role_title, organization_id)
    values (auth.uid(), '', coalesce(p_admin_full_name, 'Administrador'), 'Administrador', v_org_id)
    returning id into v_staff_id;
  end if;

  return v_org_id;
end;
$$;
