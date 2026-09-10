-- =============================================================================
-- 0123_billing_anomalies.sql — Las anomalías de facturación aterrizan en una tabla
-- consultable y con estado, no en un raise notice que nadie lee (verificación §4).
-- =============================================================================
-- 0119/0122 detectaban "dos suscripciones vivas a la vez" con un raise notice. Un
-- notice va a los logs de Postgres → invisible → el caso real (un centro pagando
-- dos veces) se pierde. Esta tabla lo hace visible, con tres cuidados (Cowork):
--
--   2.1 UNA fila por ANOMALÍA, no por evento: upsert por (org, kind, par de subs),
--       con seen_count y last_seen_at. Sin esto, un mes con dos subs vivas es una
--       fila por renovación.
--   2.2 Estado abierto/resuelto: NACE ABIERTA y se RESUELVE cuando una de las dos
--       suscripciones se cancela. Una recontratación DESORDENADA (el 'created' de la
--       nueva llega antes que el 'canceled' de la vieja) la levanta transitoriamente
--       —es el mismo desorden que el §7.10 maneja— y NO es un problema. Solo lo que
--       siga ABIERTO es real. Sin esto, el master aprende a ignorar la alerta.
--   2.4 Una tabla para varios 'kind' (hoy solo se escribe two_live_subscriptions;
--       lookup_key sin sembrar, firma de webhook, huérfanos, etc., caben aquí).
--
-- La consola de plataforma muestra el conteo de ABIERTAS (2.3, en el mismo cambio).
-- =============================================================================

create table if not exists public.billing_anomalies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  -- two_live_subscriptions | unknown_lookup_key | webhook_signature_failure | ...
  kind text not null,
  detail text,
  -- Par de suscripciones (canónico: menor/mayor) para el caso de dos vivas. En
  -- kinds sin par quedan '' (nunca null, para que el índice único deduplique limpio).
  sub_low text not null default '',
  sub_high text not null default '',
  status text not null default 'open' check (status in ('open', 'resolved')),
  seen_count int not null default 1,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz
);

comment on table public.billing_anomalies is
  'Anomalías de facturación visibles (no un log). Una fila por anomalía (upsert por '
  'org+kind+par de subs); nace abierta y se resuelve cuando deja de ser real. La '
  'escribe el webhook vía apply_stripe_subscription_event (service_role); SELECT '
  'solo master.';

-- Dedup: una fila por (centro, kind, par). Para two_live el org está presente.
create unique index if not exists uq_billing_anomalies_key
  on public.billing_anomalies(organization_id, kind, sub_low, sub_high);
create index if not exists idx_billing_anomalies_open
  on public.billing_anomalies(status) where status = 'open';

alter table public.billing_anomalies enable row level security;
-- SELECT solo master (la consola de plataforma). Escritura: solo la función
-- SECURITY DEFINER del webhook (service_role salta RLS) — sin policy de escritura.
create policy billing_anomalies_select on public.billing_anomalies
  for select using (public.is_master());

-- -----------------------------------------------------------------------------
-- apply_stripe_subscription_event: registra la anomalía ABIERTA al detectar dos
-- subs vivas, y la RESUELVE cuando una se cancela. Resto idéntico a 0122.
-- -----------------------------------------------------------------------------
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

  -- Al cancelarse esta suscripción, cualquier anomalía "dos vivas" que la incluyera
  -- deja de ser real → se resuelve (2.2). Cubre la recontratación desordenada.
  if v_status = 'canceled' then
    update public.billing_anomalies
      set status = 'resolved', resolved_at = now(), last_seen_at = now()
    where kind = 'two_live_subscriptions' and status = 'open'
      and organization_id = p_organization_id
      and (sub_low = p_stripe_subscription_id or sub_high = p_stripe_subscription_id);
  end if;

  -- SUPERSEDIDA: evento tardío de una suscripción vieja mientras otra ya es la viva.
  if v_status = 'canceled'
     and v_current_sub is not null
     and v_current_sub <> p_stripe_subscription_id then
    -- Cancela los derechos que SIGAN tagueados con la vieja (los de la nueva están
    -- tagueados con ella y no matchean → sobreviven). Fuga del §7.10.
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
    -- Dos suscripciones vivas. Se registra ABIERTA (upsert por par: 1 fila por
    -- anomalía, no por evento). Se resuelve sola cuando llegue la cancelación de una.
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

    if v_lookup is null then
      raise notice 'apply_stripe_subscription_event: item sin lookup_key, se omite (sub %).',
        p_stripe_subscription_id;
      continue;
    end if;

    select kind, key into v_kind, v_key
    from public.billing_catalog where lookup_key = v_lookup;
    if v_kind is null then
      raise exception
        'BILLING_UNKNOWN_LOOKUP_KEY: % no está en billing_catalog.', v_lookup;
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
