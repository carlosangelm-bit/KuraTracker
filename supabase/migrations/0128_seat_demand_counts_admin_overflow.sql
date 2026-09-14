-- =============================================================================
-- 0128_seat_demand_counts_admin_overflow.sql — Cierra la regresión de ff201e7.
-- =============================================================================
-- ff201e7 retiró SEAT_REQUIRES_ADMIN_MODULE: un usuario solo-administrativo que no
-- cabe en los cupos incluidos (sin module:admin, o del 4º en adelante con él) pasa a
-- consumir un asiento CLÍNICO. Pero assert_seat_available validaba solo contra
-- consumed_clinical_seats, que NO cuenta a los administrativos → el asiento cobrado
-- en la puerta quedaba libre otra vez.
--   Repro: seat:clinico=2, sin module:admin → 1 clínico (pasa), 1 solo-admin (pasa),
--   2º clínico (pasaba): 3 personas activas en 2 asientos. Inalcanzable antes porque
--   el módulo era obligatorio desde el 2º usuario; retirarlo lo destapó.
--
-- Invariante (una sola definición, §6 de este repo):
--   demanda = consumed_clinical_seats
--           + max(0, consumed_admin_slots − cupos_admin_incluidos)
--   cupos_admin_incluidos = 3 si module:admin activo, 0 si no.
--
-- Los dos contadores existentes NO se tocan (se siguen mostrando por separado en el
-- panel). Se agrega consumed_seat_demand() y assert_seat_available compara contra ella
-- en las DOS ramas que revisan el tope clínico — llamando a la función, no repitiendo
-- la expresión inline.
-- =============================================================================

-- 1. La DEMANDA de asientos clínicos: clínicos + administrativos desbordados.
create or replace function public.consumed_seat_demand(p_org uuid)
returns integer language sql stable security definer
set search_path = public, pg_temp
as $$
  select public.consumed_clinical_seats(p_org)
    + greatest(0,
        public.consumed_admin_slots(p_org)
        - case when exists (
            select 1 from public.org_entitlements e
            where e.organization_id = p_org and e.kind = 'module' and e.key = 'admin'
              and e.status = 'active') then 3 else 0 end);
$$;

comment on function public.consumed_seat_demand(uuid) is
  'Demanda de asientos CLÍNICOS del centro: consumed_clinical_seats + los '
  'administrativos puros que no caben en los cupos incluidos (3 con module:admin, '
  '0 sin él). Un administrativo desbordado consume asiento clínico.';

grant execute on function public.consumed_seat_demand(uuid) to authenticated;

-- 2. El guard del alta valida contra la DEMANDA, no contra el contador clínico solo.
create or replace function public.assert_seat_available(p_org uuid, p_roles public.user_role[])
returns void language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- "consume asiento clínico" = clínico-capaz O enfermería (consumes_clinical_seat).
  v_has_clinical boolean := coalesce(public.consumes_clinical_seat(p_roles, null::public.user_role), false);
  v_has_admin boolean := ('admin'::public.user_role = any(p_roles));
  v_has_admin_module boolean;
  v_clinical_cap int;
  v_demand int;
  v_admin_used int;
begin
  -- Cuidador puro (sin rol clínico ni admin) no consume nada.
  if not v_has_clinical and not v_has_admin then
    return;
  end if;

  v_has_admin_module := exists (
    select 1 from public.org_entitlements e
    where e.organization_id = p_org and e.kind = 'module' and e.key = 'admin'
      and e.status = 'active');

  select coalesce(max(quantity), 0) into v_clinical_cap
  from public.org_entitlements e
  where e.organization_id = p_org and e.kind = 'seat' and e.key = 'clinico'
    and e.status = 'active';

  -- Con rol clínico: suma 1 a la demanda (un asiento clínico más).
  if v_has_clinical then
    v_demand := public.consumed_seat_demand(p_org);
    if v_demand + 1 > v_clinical_cap then
      raise exception 'SEAT_NO_CLINICAL: no hay asientos clínicos disponibles (% de % en uso).', v_demand, v_clinical_cap;
    end if;
    return;
  end if;

  -- Solo administrativo: si cabe en un cupo admin INCLUIDO (3 con module:admin), no
  -- toca la demanda clínica.
  v_admin_used := public.consumed_admin_slots(p_org);
  if v_has_admin_module and v_admin_used < 3 then
    return;
  end if;
  -- Se desborda a asiento clínico → valida contra la DEMANDA total (que ya incluye a
  -- los administrativos sin cupo). Mismo criterio que la rama clínica: una sola regla.
  v_demand := public.consumed_seat_demand(p_org);
  if v_demand + 1 > v_clinical_cap then
    raise exception 'SEAT_NO_CLINICAL: no hay asientos clínicos disponibles (% de % en uso).', v_demand, v_clinical_cap;
  end if;
end;
$$;

grant execute on function public.assert_seat_available(uuid, public.user_role[]) to authenticated;
