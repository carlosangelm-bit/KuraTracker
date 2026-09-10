-- =============================================================================
-- 0119_apply_stripe_subscription_event.sql — Idempotencia ATÓMICA del webhook de
-- suscripciones (Fase 2, §4.1).
-- =============================================================================
-- El parche de fase 1 a stripe-webhook registra el evento ANTES de procesar y
-- sigue: si un paso posterior falla, el evento queda como procesado y el reintento
-- se descarta → derecho perdido. En el cobro a pacientes no importa (la función
-- nunca devuelve error); en licencias sería un cliente que pagó sin derechos.
--
-- Esta función registra el evento Y aplica los derechos en la MISMA transacción:
--   · si el event_id choca contra la PK → 'already_processed', sin efectos;
--   · si algún paso falla → raise; TODO se revierte, incluido el registro del
--     evento; la función Deno devuelve 5xx y Stripe reintenta.
--
-- El barrido de cancelación se ACOTA a la suscripción (p_stripe_subscription_id):
-- un centro puede tener transitoriamente dos suscripciones (recontratación:
-- cancelar A, crear B), y sin acotar, un evento de A cancelaría los derechos de B.
-- Además mantiene organizations.stripe_subscription_id (viva o null) para que
-- license-checkout enrute la 2ª compra a ACTUALIZAR en vez de crear otra.
--
-- SECURITY DEFINER: escribe org_entitlements saltando la RLS (que es master-only);
-- la llama SOLO el webhook con service_role. p_items = items de la suscripción:
--   [{lookup_key, quantity, subscription_item_id}, ...]
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
  v_clinico_qty int := 0;
  v_applied jsonb := '[]'::jsonb;   -- array de "kind:key" ya aplicados (incl. derivados)
  v_current_sub text;
begin
  -- Idempotencia atómica: el registro y los efectos van juntos.
  insert into public.stripe_events (event_id, type)
    values (p_event_id, coalesce(p_type, 'unknown'))
    on conflict (event_id) do nothing;
  if not found then
    return 'already_processed';
  end if;

  -- Estado del derecho derivado del estado de la suscripción.
  v_status := case p_subscription_status
                when 'active' then 'active'
                when 'trialing' then 'active'
                when 'past_due' then 'past_due'
                when 'unpaid' then 'past_due'
                when 'canceled' then 'canceled'
                when 'incomplete_expired' then 'canceled'
                else 'past_due'   -- desconocido/incompleto: no se concede acceso.
              end;

  -- SUPERSEDIDA: el upsert es por (org, kind, key) —una fila por concepto, SIN la
  -- suscripción—, así que un evento tardío de una suscripción VIEJA pisaría las
  -- filas ya escritas por la nueva antes de que el barrido acotado pudiera actuar.
  -- Caso: se cancela A, se crea B, y el 'deleted' de A (o cualquier evento suyo,
  -- que el re-fetch trae ya 'canceled') llega DESPUÉS de que B quedó registrada.
  -- El evento ya quedó en stripe_events (arriba) → no se reintenta; pero NO se
  -- tocan derechos. La columna de organizations ya apunta a B y no se toca.
  select stripe_subscription_id into v_current_sub
  from public.organizations where id = p_organization_id;

  if v_status = 'canceled'
     and v_current_sub is not null
     and v_current_sub <> p_stripe_subscription_id then
    return 'superseded';
  end if;
  if v_status <> 'canceled'
     and v_current_sub is not null
     and v_current_sub <> p_stripe_subscription_id then
    -- Anomalía: dos suscripciones vivas a la vez para el mismo centro. No se
    -- bloquea (se aplica la de este evento), pero queda en el log para revisar.
    raise notice 'apply_stripe_subscription_event: dos suscripciones vivas para el centro % (registrada %, evento %).',
      p_organization_id, v_current_sub, p_stripe_subscription_id;
  end if;

  -- Aplicar cada item de la suscripción, traducido por billing_catalog.
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_lookup := v_item->>'lookup_key';
    v_qty := coalesce((v_item->>'quantity')::int, 0);
    v_sub_item_id := v_item->>'subscription_item_id';

    -- lookup_key AUSENTE (price sin clave): reintentar no lo arregla → se omite el
    -- item (se registra). Distinto de una clave PRESENTE pero no sembrada, que sí
    -- rompe la tx a propósito (abajo) para que se siembre y el reintento entre.
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

  -- §2: module:clinico se DERIVA de los asientos clínicos. El catálogo vende lo
  -- clínico por asiento; el candado de 0115 exige module:clinico para encender el
  -- expediente. Con ≥1 asiento clínico se escribe module:clinico (mismo estado y
  -- periodo); sin asientos clínicos NO se escribe → el barrido de abajo lo cancela.
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

  -- Los derechos de ESTA suscripción que YA NO aparecen (ni derivados) pasan a
  -- canceled. Acotado a p_stripe_subscription_id: un evento de otra suscripción del
  -- mismo centro no toca éstos. No se borran (el rastro importa). source='master'
  -- NUNCA se toca: es lo que deja al master regalar/reparar sin que la renovación
  -- lo borre.
  update public.org_entitlements e
    set status = 'canceled', updated_at = now()
  where e.organization_id = p_organization_id
    and e.source = 'stripe'
    and e.stripe_subscription_id is not distinct from p_stripe_subscription_id
    and e.status <> 'canceled'
    and not (v_applied ? (e.kind || ':' || e.key));

  -- La suscripción viva del centro (para enrutar la 2ª compra). Se fija al estar
  -- activa/impaga; se limpia al cancelarse SI es la que estaba registrada (no pisa
  -- una suscripción B más nueva con el 'deleted' tardío de A).
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

comment on function public.apply_stripe_subscription_event(text, text, uuid, text, text, timestamptz, jsonb) is
  'Aplica un evento de suscripción de Stripe (idempotente y atómico): registra el '
  'event_id y hace upsert de org_entitlements en la misma transacción, acotando el '
  'barrido de cancelación a la suscripción. Deriva module:clinico de los asientos '
  'clínicos (§2). Mantiene organizations.stripe_subscription_id. source=master '
  'intacto. La llama el webhook stripe-subscription-webhook con service_role.';

grant execute on function public.apply_stripe_subscription_event(
  text, text, uuid, text, text, timestamptz, jsonb) to service_role;
