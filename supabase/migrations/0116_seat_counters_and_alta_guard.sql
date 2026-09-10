-- =============================================================================
-- 0116_seat_counters_and_alta_guard.sql — Dos contadores de asiento + tope en el
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
-- consumed_seats() (0106) se CONSERVA: lo usó el backfill 0114 (seat:clinico) y no
-- se reescribe una función vigente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. AUTORIDAD clínica POR PERFIL (una sola definición de "quién define planes").
--    Réplica de AppUser.canDiagnose: 'clinico' en el conjunto efectivo, con el
--    relleno admin→{admin,clinico} cuando roles viene vacío. Los contadores de
--    asiento miden por PERFIL (no por la membresía), para que la gerencia clínica
--    de hospital consuma su asiento clínico y no un cupo administrativo gratis
--    (falla SILENCIOSA: nadie la ve). OJO: los contadores NO usan esta función
--    directamente, sino consumes_clinical_seat (0b), que la COMPONE con enfermería
--    — definir planes y consumir asiento son preguntas distintas.
--
--    IMPORTANTE: este cuerpo es IDÉNTICO al de 0112_capable_clinico_by_profile,
--    que en esta rama (rebasada sobre staging) ya vive AGUAS ARRIBA y se aplica
--    ANTES (0112 < 0116). Ambos usan create-or-replace, así que el ORDEN no importa:
--    la que corra al final —esta, 0116— escribe el mismo cuerpo. Si se cambia una,
--    cambiar la otra igual. En el merge a main (sin motor de visión) esta 0116 viaja
--    con licencia; 0112 llega por la rama fix/prevent-org-without-clinico, y como el
--    cuerpo es idéntico da igual cuál gane. Aquí, además, se COMPONE con enfermería
--    en consumes_clinical_seat (0b), que 0112 no trae.
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
-- 0b. Consumir ASIENTO CLÍNICO es OTRA pregunta que definir planes.
--    profile_can_define_plans responde "¿tiene autoridad clínica?" — y por diseño
--    (0045) enfermería NO diagnostica ni cambia protocolo, así que queda fuera.
--    Pero enfermería SÍ usa el módulo clínico: consume asiento clínico y no un
--    cupo admin gratis. Se COMPONEN, no se sustituyen: clínico-capaz (con el
--    relleno admin de arriba) O enfermería (con el mismo relleno por el escalar
--    cuando roles viene vacío). Encapsulado aparte para que nadie vuelva a
--    confundir "definir planes" (autoridad) con "consumir asiento" (uso).
--    assert_seat_available ya cobraba asiento a enfermería (su v_has_clinical la
--    incluye); sin esto, el contador NO la contaba → altas de enfermería SIN tope
--    (fuga silenciosa, y en una clínica de heridas enfermería es la mayoría).
create or replace function public.consumes_clinical_seat(
  p_roles public.user_role[], p_role public.user_role
) returns boolean
language sql
immutable
as $$
  select public.profile_can_define_plans(p_roles, p_role)
    or case
         when coalesce(cardinality(p_roles), 0) > 0
           then 'enfermeria' = any(p_roles::text[])
         else p_role::text = 'enfermeria'
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
    and public.consumes_clinical_seat(p.roles, p.role);
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
    and not public.consumes_clinical_seat(p.roles, p.role)
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
  -- Misma regla que los contadores: "consume asiento clínico" = clínico-capaz O
  -- enfermería. Se llama a consumes_clinical_seat (0b) en vez de repetir el unnest,
  -- para no tener dos definiciones de la misma regla (§6). p_roles aquí es el
  -- conjunto que se está asignando; el escalar del fallback no aplica (no-vacío).
  -- coalesce a false: con p_roles vacío/nulo la función devuelve NULL (el case cae
  -- al escalar null) y sin el coalesce el retorno temprano del cuidador no se
  -- tomaría. Hoy el único llamante rechaza roles vacío antes; la fase 3 (alta
  -- pública) agrega uno que no, así que se blinda aquí.
  v_has_clinical boolean := coalesce(public.consumes_clinical_seat(p_roles, null::public.user_role), false);
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
  -- Plan gratuito (§2): sin suscripción en Stripe, los derechos se escriben a mano.
  -- module:clinico es OBLIGATORIO — sin él el candado de 0115 dejaría el plan
  -- gratuito inservible (no se podría encender el expediente). seat:protocolo=1
  -- queda inerte hasta que el centro compre el add-on Kura+ (AND de 0100).
  insert into public.org_entitlements (organization_id, kind, key, quantity, status, source)
  values
    (v_org_id, 'plan',   'gratuito',  null, 'active', 'master'),
    (v_org_id, 'module', 'clinico',   null, 'active', 'master'),
    (v_org_id, 'seat',   'clinico',   1,    'active', 'master'),
    (v_org_id, 'seat',   'protocolo', 1,    'active', 'master');

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
