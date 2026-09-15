-- =============================================================================
-- 0138_org_entitlement_vigente.sql — Matriz del protocolo · etapa 1.5
-- =============================================================================
-- UNA sola autoridad de "derecho vigente" en SQL, antes de la etapa 2 (el resolvedor que
-- viene tendría que preguntar lo mismo y quedaríamos con tres definiciones). Extrae la
-- semántica que ya validó 0137 a una función y repunta a ella los tres llamantes.
--
-- Las dos ÚLTIMAS (enforce_*) CAMBIAN de conducta a propósito: pasan a respetar el
-- vencimiento (source='master' con current_period_end en el pasado deja de contar). Ese es
-- el ARREGLO, no un efecto secundario: hasta hoy el SQL miraba solo status y discrepaba del
-- Dart (data_repository.canWriteModule), que sí distingue por origen. Consecuencia medida
-- antes de aplicar (§1.5.c): centros de prueba VENCIDOS ya no pueden encender módulos desde
-- la base.
-- =============================================================================

-- 1.5.a — La definición ÚNICA. Misma semántica que 0137: status='active' Y asimetría por
-- origen (stripe no mira fecha; master sí, para que un otorgamiento a mano venza por tiempo,
-- que es la única verdad — nadie externo avisa).
create or replace function public.org_entitlement_vigente(p_org uuid, p_kind text, p_key text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.org_entitlements e
    where e.organization_id = p_org
      and e.kind = p_kind
      and e.key = p_key
      and e.status = 'active'
      and (
        e.source = 'stripe'
        or (e.source = 'master'
            and (e.current_period_end is null or e.current_period_end > now()))
      )
  );
$$;
comment on function public.org_entitlement_vigente(uuid, text, text) is
  'ÚNICA autoridad de "derecho vigente" en SQL. status=active Y (stripe | (master Y no '
  'vencido por current_period_end)). Toda función que consulte vigencia de org_entitlements '
  'DEBE pasar por aquí (guarda 1.5.d), para que no nazca una cuarta definición en silencio.';

-- 1.5.b — Repunta los tres llamantes, SIN cambiar su conducta visible salvo el vencimiento.

-- (i) protocol:author (0137) — conducta idéntica (0137 ya tenía la asimetría).
create or replace function public.current_org_has_protocol_author()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.org_entitlement_vigente(public.current_organization_id(), 'module', 'protocol:author');
$$;

-- (ii) module_settings: encender un módulo exige el derecho de visibilidad (module:clinico).
-- AHORA respeta el vencimiento (antes: solo status). Resto idéntico a 0121 §2.
create or replace function public.enforce_module_requires_entitlement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_required text;
  v_label text;
begin
  if new.enabled is not true then
    return new;
  end if;
  if public.is_master() then
    return new;
  end if;

  v_required := 'clinico';
  v_label := 'Clínico';

  if not public.org_entitlement_vigente(new.organization_id, 'module', v_required) then
    raise exception 'El centro no tiene contratado el módulo %.', v_label;
  end if;

  return new;
end;
$$;

-- (iii) premium por usuario: exige la bandera legada O el add-on seat:protocolo VIGENTE.
-- La vigencia pasa por la autoridad; el cupo (quantity>=1) es propio del asiento y se queda.
-- AHORA respeta el vencimiento. Resto idéntico a 0121 §3.
create or replace function public.enforce_premium_requires_org_addon()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.premium_enabled = true
     and (tg_op = 'INSERT'
          or coalesce(old.premium_enabled, false) is distinct from new.premium_enabled) then
    if not exists (
      select 1 from public.organizations o
      where o.id = new.organization_id and o.premium_protocolo_kura = true
    ) and not (
      public.org_entitlement_vigente(new.organization_id, 'seat', 'protocolo')
      and coalesce((
        select e.quantity from public.org_entitlements e
        where e.organization_id = new.organization_id
          and e.kind = 'seat' and e.key = 'protocolo'
      ), 0) >= 1
    ) then
      raise exception
        'El centro no tiene el add-on Protocolo Kura+; no se puede activar premium por usuario.';
    end if;
  end if;
  return new;
end;
$$;
