-- =============================================================================
-- 0133_stripe_takeover_clears_master_fields.sql — Cuando Stripe vende un derecho
-- que YA estaba otorgado a mano, el upsert del webhook cambia source a 'stripe'
-- pero dejaba grant_type/reason/granted_by/is_permanent con los valores del
-- otorgamiento manual → el CHECK ent_master_grant_shape (0132) rechaza la fila y el
-- webhook SE CAE. El job migrations no lo ve: hace falta un evento de Stripe.
--
-- (a) apply_stripe_subscription_event: los dos upserts (cada ítem y el module:clinico
--     derivado) limpian los cuatro campos manuales en su DO UPDATE, y se escribe una
--     fila en org_entitlement_log con action='stripe_takeover' cuando la fila venía de
--     un otorgamiento manual (para no perder el cambio de dueño).
-- (b) La guardia 2 de master_grant_entitlement/master_revoke_entitlement rebota SOLO
--     cuando la fila de Stripe está viva (status in ('active','past_due')). Una fila
--     de Stripe CANCELADA sí se puede tomar a mano (dejar cortesía a quien dejó de
--     pagar); al tomarla, se limpian stripe_subscription_item_id/stripe_subscription_id
--     (simétrico a (a)).
--
-- Resto del cuerpo de apply_stripe_subscription_event: idéntico a 0131 (deriva de
-- precio por clave, dos-suscripciones, superseded, cancelación de huérfanos).
-- =============================================================================

-- La bitácora admite el nuevo tipo de acción.
alter table public.org_entitlement_log
  drop constraint if exists org_entitlement_log_action_check;
alter table public.org_entitlement_log
  add constraint org_entitlement_log_action_check
  check (action in ('grant','revoke','amend','stripe_takeover'));

-- (a) --------------------------------------------------------------------------
create or replace function public.apply_stripe_subscription_event(
  p_event_id text,
  p_type text,
  p_organization_id uuid,
  p_stripe_subscription_id text,
  p_subscription_status text,
  p_current_period_end timestamptz,
  p_items jsonb
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status text;
  v_item jsonb;
  v_lookup text;
  v_qty int;
  v_sub_item_id text;
  v_kind text;
  v_key text;
  v_cat_amount int;
  v_evt_amount int;
  v_clinico_qty int := 0;
  v_applied jsonb := '[]'::jsonb;
  v_current_sub text;
  v_lo text;
  v_hi text;
  v_prev_source text;  -- 0133: dueño anterior de la fila, para detectar takeover
begin
  insert into public.stripe_events (event_id, type)
    values (p_event_id, coalesce(p_type, 'unknown'))
    on conflict (event_id) do nothing;
  if not found then
    return 'already_processed';
  end if;

  v_status := case p_subscription_status
                when 'active' then 'active'
                when 'trialing' then 'active'
                when 'past_due' then 'past_due'
                when 'unpaid' then 'past_due'
                when 'canceled' then 'canceled'
                when 'incomplete_expired' then 'canceled'
                else 'past_due'
              end;

  select stripe_subscription_id into v_current_sub
  from public.organizations where id = p_organization_id;

  if v_status = 'canceled' then
    update public.billing_anomalies
      set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where kind = 'two_live_subscriptions' and status = 'open'
      and organization_id = p_organization_id
      and (sub_low = p_stripe_subscription_id or sub_high = p_stripe_subscription_id);
  end if;

  if v_status = 'canceled'
     and v_current_sub is not null
     and v_current_sub <> p_stripe_subscription_id then
    update public.org_entitlements e
      set status = 'canceled', updated_at = now()
    where e.organization_id = p_organization_id
      and e.source = 'stripe'
      and e.stripe_subscription_id = p_stripe_subscription_id
      and e.status <> 'canceled';
    return 'superseded';
  end if;
  if v_status <> 'canceled'
     and v_current_sub is not null
     and v_current_sub <> p_stripe_subscription_id then
    v_lo := least(v_current_sub, p_stripe_subscription_id);
    v_hi := greatest(v_current_sub, p_stripe_subscription_id);
    insert into public.billing_anomalies
      (organization_id, kind, detail, sub_low, sub_high)
    values
      (p_organization_id, 'two_live_subscriptions',
       'Dos suscripciones vivas a la vez; se aplicó la del evento.', v_lo, v_hi)
    on conflict (organization_id, kind, sub_low, sub_high, scope_key) do update set
      seen_count = public.billing_anomalies.seen_count + 1,
      last_seen_at = now(),
      status = 'open',
      resolved_at = null;
    raise notice 'apply_stripe_subscription_event: dos suscripciones vivas para el centro % (registrada %, evento %).',
      p_organization_id, v_current_sub, p_stripe_subscription_id;
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_lookup := v_item->>'lookup_key';
    v_qty := coalesce((v_item->>'quantity')::int, 0);
    v_sub_item_id := v_item->>'subscription_item_id';
    v_evt_amount := (v_item->>'unit_amount')::int;

    if v_lookup is null then
      raise notice 'apply_stripe_subscription_event: item sin lookup_key, se omite (sub %).',
        p_stripe_subscription_id;
      continue;
    end if;

    select kind, key, unit_amount into v_kind, v_key, v_cat_amount
    from public.billing_catalog where lookup_key = v_lookup;
    if v_kind is null then
      raise exception
        'BILLING_UNKNOWN_LOOKUP_KEY: % no está en billing_catalog.', v_lookup;
    end if;

    -- Deriva de precio: una fila POR clave (scope_key = lookup_key), con su propio
    -- seen_count; se resuelve por separado. Solo si ambos montos están presentes.
    if v_cat_amount is not null and v_evt_amount is not null
       and v_cat_amount <> v_evt_amount then
      insert into public.billing_anomalies (organization_id, kind, detail, scope_key)
      values (p_organization_id, 'catalog_price_drift',
        format('%s: catálogo=%s, Stripe=%s (centavos).',
               v_lookup, v_cat_amount, v_evt_amount),
        v_lookup)
      on conflict (organization_id, kind, sub_low, sub_high, scope_key) do update set
        detail = excluded.detail,
        seen_count = public.billing_anomalies.seen_count + 1,
        last_seen_at = now(),
        status = 'open',
        resolved_at = null;
      raise notice 'apply_stripe_subscription_event: deriva de precio en % (catálogo % vs Stripe %).',
        v_lookup, v_cat_amount, v_evt_amount;
    end if;

    -- 0133: ¿quién era el dueño de esta fila ANTES del upsert?
    select source into v_prev_source from public.org_entitlements
     where organization_id = p_organization_id and kind = v_kind and key = v_key;

    insert into public.org_entitlements
      (organization_id, kind, key, quantity, status, current_period_end,
       stripe_subscription_item_id, stripe_subscription_id, source, updated_at)
    values
      (p_organization_id, v_kind, v_key,
       case when v_kind = 'seat' then greatest(v_qty, 0) else null end,
       v_status, p_current_period_end, v_sub_item_id, p_stripe_subscription_id, 'stripe', now())
    on conflict (organization_id, kind, key) do update set
      quantity = excluded.quantity,
      status = excluded.status,
      current_period_end = excluded.current_period_end,
      stripe_subscription_item_id = excluded.stripe_subscription_item_id,
      stripe_subscription_id = excluded.stripe_subscription_id,
      source = 'stripe',
      -- 0133: Stripe toma la fila → limpiar los campos del otorgamiento manual, o el
      -- CHECK ent_master_grant_shape (rama stripe = todos nulos) rechaza la fila.
      grant_type = null,
      reason = null,
      granted_by = null,
      is_permanent = false,
      updated_at = now();

    -- 0133: si la fila venía de un otorgamiento manual, deja rastro del cambio de dueño.
    if v_prev_source = 'master' then
      insert into public.org_entitlement_log
        (organization_id, kind, key, action, quantity, current_period_end,
         is_permanent, actor)
      values
        (p_organization_id, v_kind, v_key, 'stripe_takeover',
         case when v_kind = 'seat' then greatest(v_qty, 0) else null end,
         p_current_period_end, false, auth.uid());
    end if;

    v_applied := v_applied || to_jsonb(v_kind || ':' || v_key);
    if v_kind = 'seat' and v_key = 'clinico' then
      v_clinico_qty := v_clinico_qty + greatest(v_qty, 0);
    end if;
  end loop;

  if v_clinico_qty >= 1 then
    -- 0133: dueño anterior del module:clinico derivado.
    select source into v_prev_source from public.org_entitlements
     where organization_id = p_organization_id and kind = 'module' and key = 'clinico';

    insert into public.org_entitlements
      (organization_id, kind, key, quantity, status, current_period_end,
       stripe_subscription_id, source, updated_at)
    values
      (p_organization_id, 'module', 'clinico', null, v_status, p_current_period_end,
       p_stripe_subscription_id, 'stripe', now())
    on conflict (organization_id, kind, key) do update set
      status = excluded.status,
      current_period_end = excluded.current_period_end,
      stripe_subscription_id = excluded.stripe_subscription_id,
      source = 'stripe',
      -- 0133: mismo saneamiento que el upsert por ítem.
      grant_type = null,
      reason = null,
      granted_by = null,
      is_permanent = false,
      updated_at = now();

    if v_prev_source = 'master' then
      insert into public.org_entitlement_log
        (organization_id, kind, key, action, quantity, current_period_end,
         is_permanent, actor)
      values
        (p_organization_id, 'module', 'clinico', 'stripe_takeover', null,
         p_current_period_end, false, auth.uid());
    end if;

    v_applied := v_applied || to_jsonb('module:clinico'::text);
  end if;

  update public.org_entitlements e
    set status = 'canceled', updated_at = now()
  where e.organization_id = p_organization_id
    and e.source = 'stripe'
    and e.stripe_subscription_id is not distinct from p_stripe_subscription_id
    and e.status <> 'canceled'
    and not (v_applied ? (e.kind || ':' || e.key));

  if v_status = 'canceled' then
    update public.organizations
      set stripe_subscription_id = null
      where id = p_organization_id
        and stripe_subscription_id = p_stripe_subscription_id;
  else
    update public.organizations
      set stripe_subscription_id = p_stripe_subscription_id
      where id = p_organization_id;
  end if;

  return 'applied';
end;
$$;

grant execute on function public.apply_stripe_subscription_event(
  text, text, uuid, text, text, timestamptz, jsonb) to service_role;

-- (b) --------------------------------------------------------------------------
-- Guardia 2 corregida: solo rebota si la fila de Stripe está VIVA. Una cancelada
-- se puede tomar a mano; al tomarla se limpian los ids de Stripe.
create or replace function public.master_grant_entitlement(
  p_org uuid,
  p_kind text,
  p_key text,
  p_quantity int,
  p_grant_type text,
  p_reason text,
  p_until timestamptz,
  p_permanent boolean
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_existing public.org_entitlements%rowtype;
  v_found boolean;
  v_demand int;
  v_cpe timestamptz;
  v_action text;
  v_id uuid;
begin
  -- 1) Solo el master.
  if not public.is_master() then
    raise exception 'MASTER_ONLY';
  end if;

  select * into v_existing
    from public.org_entitlements
   where organization_id = p_org and kind = p_kind and key = p_key;
  v_found := found;

  -- 2) No pisar un derecho de Stripe VIVO (rompería el barrido de 0119). Una fila
  --    de Stripe CANCELADA sí se puede tomar a mano (cortesía a quien dejó de pagar).
  if v_found and v_existing.source = 'stripe'
     and v_existing.status in ('active', 'past_due') then
    raise exception 'GRANT_STRIPE_OWNED: ese derecho lo gobierna Stripe.';
  end if;

  -- 3) No bajar el tope de asientos clínicos por debajo de lo que ya se usa.
  if p_kind = 'seat' and p_key = 'clinico' then
    v_demand := public.consumed_seat_demand(p_org);
    if p_quantity < v_demand then
      raise exception 'GRANT_BELOW_DEMAND: el centro ya usa % asientos.', v_demand;
    end if;
  end if;

  -- 4) Vigencia obligatoria salvo permanente deliberado.
  if not p_permanent and p_until is null then
    raise exception 'GRANT_NO_EXPIRY';
  end if;

  -- 5) Permanente Y fecha a la vez es ambiguo.
  if p_permanent and p_until is not null then
    raise exception 'GRANT_AMBIGUOUS_EXPIRY';
  end if;

  v_cpe := case when p_permanent then null else p_until end;
  v_action := case when v_found then 'amend' else 'grant' end;

  insert into public.org_entitlements (
    organization_id, kind, key, quantity, status, source,
    current_period_end, grant_type, reason, granted_by, is_permanent
  ) values (
    p_org, p_kind, p_key, p_quantity, 'active', 'master',
    v_cpe, p_grant_type, p_reason, auth.uid(), p_permanent
  )
  on conflict (organization_id, kind, key) do update set
    quantity           = excluded.quantity,
    status             = 'active',
    source             = 'master',
    current_period_end = excluded.current_period_end,
    grant_type         = excluded.grant_type,
    reason             = excluded.reason,
    granted_by         = excluded.granted_by,
    is_permanent       = excluded.is_permanent,
    -- 0133: al tomar a mano una fila de Stripe cancelada, soltar sus ids (simétrico
    -- a que Stripe limpia los campos manuales al tomar la fila).
    stripe_subscription_item_id = null,
    stripe_subscription_id      = null
  returning id into v_id;

  insert into public.org_entitlement_log (
    organization_id, kind, key, action, grant_type, reason, quantity,
    current_period_end, is_permanent, actor
  ) values (
    p_org, p_kind, p_key, v_action, p_grant_type, p_reason, p_quantity,
    v_cpe, p_permanent, auth.uid()
  );

  return v_id;
end;
$$;

create or replace function public.master_revoke_entitlement(
  p_org uuid,
  p_kind text,
  p_key text,
  p_reason text
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_existing public.org_entitlements%rowtype;
begin
  if not public.is_master() then
    raise exception 'MASTER_ONLY';
  end if;

  select * into v_existing
    from public.org_entitlements
   where organization_id = p_org and kind = p_kind and key = p_key;

  -- Guardia 2 corregida: solo un derecho de Stripe VIVO se defiende.
  if found and v_existing.source = 'stripe'
     and v_existing.status in ('active', 'past_due') then
    raise exception 'GRANT_STRIPE_OWNED: ese derecho lo gobierna Stripe.';
  end if;

  update public.org_entitlements
     set status = 'canceled'
   where organization_id = p_org and kind = p_kind and key = p_key;

  insert into public.org_entitlement_log (
    organization_id, kind, key, action, grant_type, reason, quantity,
    current_period_end, is_permanent, actor
  ) values (
    p_org, p_kind, p_key, 'revoke', v_existing.grant_type, p_reason,
    v_existing.quantity, v_existing.current_period_end, v_existing.is_permanent,
    auth.uid()
  );
end;
$$;

grant execute on function public.master_grant_entitlement(
  uuid, text, text, int, text, text, timestamptz, boolean) to authenticated;
grant execute on function public.master_revoke_entitlement(
  uuid, text, text, text) to authenticated;
