-- =============================================================================
-- 0127_admin_module_optional_for_seat.sql — Administración deja de ser obligatoria.
-- =============================================================================
-- Decisión de negocio (Carlos, 12-sep): las funciones administrativas BÁSICAS van
-- incluidas con la licencia clínica. Solo el módulo AVANZADO se cobra ($1,200, sigue
-- incluyendo 3 cupos administrativos). En el guard del alta esto significa retirar el
-- bloque que exigía module:admin a partir del 2º usuario (SEAT_REQUIRES_ADMIN_MODULE).
--
-- POR QUÉ ESTA MIGRACIÓN Y NO SOLO EDITAR 0116:
--   0116 se edita EN SU LUGAR (Carlos) para que un apply DESDE CERO (el futuro merge a
--   main/prod, hoy en 0107) nazca ya con la regla nueva. Pero `supabase db push` NO
--   re-aplica una migración ya registrada, y STAGING ya aplicó 0116 (0117-0126 corren
--   sobre él). Editar 0116 sería INERTE en staging. Esta migración additiva hace un
--   create-or-replace del guard con el cuerpo nuevo para que el cambio SÍ aterrice en
--   staging. En un apply desde cero, 0116 escribe el cuerpo nuevo y esta lo re-escribe
--   idéntico (idempotente) — mismo patrón tolerado que 0112 ≡ 0116. Si se cambia una,
--   cambiar la otra.
--
-- El cuerpo es IDÉNTICO al de 0116 ya editado: contadores intactos, con rol clínico
-- consume asiento clínico; solo-administrativo entra en los 3 cupos si hay module:admin
-- y si no (o del 4º en adelante) consume asiento clínico. Lo único retirado: el bloque
-- SEAT_REQUIRES_ADMIN_MODULE y su conteo de miembros.
-- =============================================================================

create or replace function public.assert_seat_available(p_org uuid, p_roles public.user_role[])
returns void language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- "consume asiento clínico" = clínico-capaz O enfermería (consumes_clinical_seat, 0116 0b).
  -- coalesce a false: con p_roles vacío/nulo la función devuelve NULL y sin el coalesce
  -- el retorno temprano del cuidador no se tomaría.
  v_has_clinical boolean := coalesce(public.consumes_clinical_seat(p_roles, null::public.user_role), false);
  v_has_admin boolean := ('admin'::public.user_role = any(p_roles));
  v_has_admin_module boolean;
  v_clinical_cap int;
  v_clinical_used int;
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

  -- Administración BÁSICA incluida: ya NO se exige module:admin para un 2º usuario.
  -- Sin el módulo, un usuario solo-administrativo consume un asiento clínico (abajo).

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
