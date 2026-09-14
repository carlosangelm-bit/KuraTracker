-- =============================================================================
-- 0130_catalog_price_drift_anomaly.sql — Vigila que el precio de billing_catalog no
-- se desincronice del que Stripe cobra.
-- =============================================================================
-- 0129 guardó los montos en billing_catalog para mostrarlos sin llamar a Stripe.
-- Pero Stripe SIGUE cobrando: si alguien cambia un price en Stripe y no replica el
-- unit_amount en la base, la app muestra un precio y se cobra otro. Esta es la
-- objeción que justificó no escribir precios a mano — aquí se cierra.
--
-- El webhook ya manda unit_amount por ítem (monto que Stripe cobró). Esta versión de
-- apply_stripe_subscription_event lo compara contra billing_catalog.unit_amount del
-- MISMO lookup_key; si difieren, abre una billing_anomalies kind='catalog_price_drift'
-- con los dos montos y la clave en detail. Upsert por (organization_id, kind) — el
-- índice único de 0123 con sub_low/sub_high vacíos → una fila por centro.
--
-- Todo lo demás es IDÉNTICO a 0123 (create-or-replace de la función completa: solo se
-- agrega, en el loop de ítems, la lectura de unit_amount y el chequeo de deriva).
-- =============================================================================

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
  v_cat_amount int;   -- unit_amount del catálogo (lo que la app muestra)
  v_evt_amount int;   -- unit_amount del evento (lo que Stripe cobra)
  v_clinico_qty int := 0;
  v_applied jsonb := '[]'::jsonb;
  v_current_sub text;
  v_lo text;
  v_hi text;
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
    on conflict (organization_id, kind, sub_low, sub_high) do update set
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
    v_evt_amount := (v_item->>'unit_amount')::int;  -- puede venir null

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

    -- Deriva de precio: el catálogo (lo que se muestra) ≠ lo que Stripe cobra. Solo
    -- si ambos montos están presentes; una fila sin unit_amount no dispara ruido.
    if v_cat_amount is not null and v_evt_amount is not null
       and v_cat_amount <> v_evt_amount then
      insert into public.billing_anomalies (organization_id, kind, detail)
      values (p_organization_id, 'catalog_price_drift',
        format('%s: catálogo=%s, Stripe=%s (centavos).',
               v_lookup, v_cat_amount, v_evt_amount))
      on conflict (organization_id, kind, sub_low, sub_high) do update set
        detail = excluded.detail,
        seen_count = public.billing_anomalies.seen_count + 1,
        last_seen_at = now(),
        status = 'open',
        resolved_at = null;
      raise notice 'apply_stripe_subscription_event: deriva de precio en % (catálogo % vs Stripe %).',
        v_lookup, v_cat_amount, v_evt_amount;
    end if;

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
      updated_at = now();

    v_applied := v_applied || to_jsonb(v_kind || ':' || v_key);
    if v_kind = 'seat' and v_key = 'clinico' then
      v_clinico_qty := v_clinico_qty + greatest(v_qty, 0);
    end if;
  end loop;

  if v_clinico_qty >= 1 then
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
      updated_at = now();
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
