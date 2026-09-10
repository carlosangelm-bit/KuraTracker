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
-- SECURITY DEFINER: escribe org_entitlements saltando la RLS (que es master-only);
-- la llama SOLO el webhook con service_role. p_items = items de la suscripción:
--   [{lookup_key, quantity, subscription_item_id}, ...]
-- =============================================================================

create or replace function public.apply_stripe_subscription_event(
  p_event_id text,
  p_type text,
  p_organization_id uuid,
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

  -- Aplicar cada item de la suscripción, traducido por billing_catalog.
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_lookup := v_item->>'lookup_key';
    v_qty := coalesce((v_item->>'quantity')::int, 0);
    v_sub_item_id := v_item->>'subscription_item_id';

    select kind, key into v_kind, v_key
    from public.billing_catalog where lookup_key = v_lookup;
    if v_kind is null then
      -- Clave desconocida: un price creado en Stripe sin sembrarlo aquí. No se
      -- ignora en silencio — se rompe la transacción para que se vea y se siembre.
      raise exception
        'BILLING_UNKNOWN_LOOKUP_KEY: % no está en billing_catalog.', v_lookup;
    end if;

    insert into public.org_entitlements
      (organization_id, kind, key, quantity, status, current_period_end,
       stripe_subscription_item_id, source, updated_at)
    values
      (p_organization_id, v_kind, v_key,
       case when v_kind = 'seat' then greatest(v_qty, 0) else null end,
       v_status, p_current_period_end, v_sub_item_id, 'stripe', now())
    on conflict (organization_id, kind, key) do update set
      quantity = excluded.quantity,
      status = excluded.status,
      current_period_end = excluded.current_period_end,
      stripe_subscription_item_id = excluded.stripe_subscription_item_id,
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
      (organization_id, kind, key, quantity, status, current_period_end, source, updated_at)
    values
      (p_organization_id, 'module', 'clinico', null, v_status, p_current_period_end, 'stripe', now())
    on conflict (organization_id, kind, key) do update set
      status = excluded.status,
      current_period_end = excluded.current_period_end,
      source = 'stripe',
      updated_at = now();
    v_applied := v_applied || to_jsonb('module:clinico'::text);
  end if;

  -- Los derechos de Stripe que YA NO aparecen (ni derivados) pasan a canceled. No
  -- se borran (el rastro importa). source='master' NUNCA se toca desde aquí: es lo
  -- que deja al master regalar/reparar una licencia sin que la renovación la borre.
  update public.org_entitlements e
    set status = 'canceled', updated_at = now()
  where e.organization_id = p_organization_id
    and e.source = 'stripe'
    and e.status <> 'canceled'
    and not (v_applied ? (e.kind || ':' || e.key));

  return 'applied';
end;
$$;

comment on function public.apply_stripe_subscription_event(text, text, uuid, text, timestamptz, jsonb) is
  'Aplica un evento de suscripción de Stripe (idempotente y atómico): registra el '
  'event_id y hace upsert de org_entitlements en la misma transacción. Deriva '
  'module:clinico de los asientos clínicos (§2). source=master intacto. La llama '
  'el webhook stripe-subscription-webhook con service_role.';

grant execute on function public.apply_stripe_subscription_event(
  text, text, uuid, text, timestamptz, jsonb) to service_role;
