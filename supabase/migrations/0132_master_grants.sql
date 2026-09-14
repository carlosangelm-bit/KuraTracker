-- =============================================================================
-- 0132_master_grants.sql — La consola de /platform pasa a operar DERECHOS
-- (org_entitlements) en vez de interruptores legados. Etapa 1 del spec
-- "Consola master · Derechos": SOLO base (columnas, bitácora, RPCs). Sin UI.
--
-- Orden que importa: (1) columnas, (2) relleno de las filas que 0114 ya escribió,
-- (3) CHECK — al revés el CHECK rebota contra las filas viejas sin grant_type.
--
-- NO toca 0114/0115/0119. NO construye otro mecanismo de caducidad: canWriteModule
-- ya gatea por current_period_end cuando source='master'. is_permanent NO se lee
-- para decidir acceso; existe para que el CHECK distinga "permanente a propósito"
-- de "fecha olvidada".
-- =============================================================================

-- 2.1 Columnas nuevas ---------------------------------------------------------
alter table public.org_entitlements
  add column if not exists grant_type   text,   -- 'comercial' | 'cortesia'; null si stripe
  add column if not exists reason       text,   -- motivo; null si stripe
  add column if not exists granted_by   uuid references public.profiles(id),
  add column if not exists is_permanent boolean not null default false;

comment on column public.org_entitlements.is_permanent is
  'Permanente A PROPÓSITO (no "fecha olvidada"). El CHECK lo usa para distinguir; '
  'NUNCA se lee para decidir acceso — eso es current_period_end (canWriteModule).';

-- 2.2 Relleno de las filas que 0114 ya escribió (source='master', sin campos) --
-- ANTES del CHECK: si no, el CHECK rebota contra estas filas.
update public.org_entitlements
   set grant_type = 'cortesia',
       reason = 'Backfill de licencias (0114): estado efectivo al migrar.',
       is_permanent = true
 where source = 'master' and grant_type is null;

-- 2.3 CHECK, DESPUÉS del relleno ----------------------------------------------
alter table public.org_entitlements
  drop constraint if exists ent_master_grant_shape;
alter table public.org_entitlements add constraint ent_master_grant_shape check (
  (source = 'stripe'
     and grant_type is null and reason is null and granted_by is null
     and is_permanent = false)
  or (source = 'master'
     and grant_type in ('comercial','cortesia')
     and reason is not null and length(btrim(reason)) >= 10
     and (is_permanent or current_period_end is not null))
);

-- 2.4 Bitácora append-only ----------------------------------------------------
-- La unicidad (organization_id, kind, key) hace que otorgar dos veces SOBRESCRIBA;
-- sin bitácora se pierde el historial. Nunca se borra ni se actualiza.
create table if not exists public.org_entitlement_log (
  id                 uuid primary key default gen_random_uuid(),
  organization_id    uuid not null references public.organizations(id),
  kind               text not null,
  key                text not null,
  action             text not null check (action in ('grant','revoke','amend')),
  grant_type         text,
  reason             text,
  quantity           integer,
  current_period_end timestamptz,
  is_permanent       boolean,
  actor              uuid,
  at                 timestamptz not null default now()
);

alter table public.org_entitlement_log enable row level security;

-- select para master; SIN insert para authenticated (solo escriben las RPC
-- security definer, que corren como owner y no pasan por RLS).
drop policy if exists org_entitlement_log_select_master on public.org_entitlement_log;
create policy org_entitlement_log_select_master
  on public.org_entitlement_log for select
  using (public.is_master());

-- 2.5 RPCs --------------------------------------------------------------------

-- Otorgar / enmendar un derecho a mano. Guardias EN ORDEN, cada una con su
-- mensaje propio. granted_by SIEMPRE de auth.uid(), NUNCA del cliente.
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

  -- 2) LA guardia que más importa: no pisar un derecho de Stripe (rompería el
  --    barrido de apply_stripe_subscription_event de 0119).
  if v_found and v_existing.source = 'stripe' then
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
    is_permanent       = excluded.is_permanent
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

-- Revocar (no borra: el rastro importa). Mismas guardias 1 y 2.
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

  if found and v_existing.source = 'stripe' then
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

-- Activar/desactivar una cuenta. Los triggers de 0111/0112 (último capaz de
-- definir planes) siguen siendo la autoridad: si esto dejaría al centro sin quien
-- defina planes, revientan solos y el mensaje se propaga tal cual.
create or replace function public.master_set_profile_active(
  p_profile uuid,
  p_active boolean
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_master() then
    raise exception 'MASTER_ONLY';
  end if;

  update public.profiles set is_active = p_active where id = p_profile;
end;
$$;

-- grant execute SOLO a authenticated (la guardia 1 hace el resto).
grant execute on function public.master_grant_entitlement(
  uuid, text, text, int, text, text, timestamptz, boolean) to authenticated;
grant execute on function public.master_revoke_entitlement(
  uuid, text, text, text) to authenticated;
grant execute on function public.master_set_profile_active(
  uuid, boolean) to authenticated;
