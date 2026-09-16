-- Fixture MÍNIMO para ejercitar el CÓDIGO REAL de 0136 (columnas nuevas, catálogo del
-- sistema, candado protocol:author) sin la cadena completa de migraciones ni el stack de
-- Supabase. Recrea solo lo que 0076/0077/0136 tocan o referencian, con las MISMAS firmas.
-- El runner carga DESPUÉS las migraciones 0076, 0077 y 0136 reales encima de esto.
create extension if not exists pgcrypto;

-- auth.uid() de Supabase, stub: lee un GUC de prueba (test.uid).
create schema if not exists auth;
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('test.uid', true), '')::uuid
$$;

do $$ begin
  create type public.user_role as enum ('admin','clinico','master','cuidador','enfermeria');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  roles public.user_role[] not null default '{}',
  role public.user_role,
  organization_id uuid,
  is_active boolean not null default true
);

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null
);

-- inventory_items: lo que 0076 referencia por FK y lo que 0139 lee (org, site, name).
create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid,
  site_id uuid,
  name text,
  unit_cost numeric(10, 2),
  currency text default 'MXN',
  is_active boolean not null default true,
  -- par shopify (0050): puente centro→identidad que usa resolve_protocol (0140) en el catálogo.
  shopify_product_id text,
  shopify_variant_id text
);

-- org_entitlements con la forma de 0113 (kind/key/status).
create table if not exists public.org_entitlements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  kind text not null check (kind in ('plan','module','seat')),
  key text not null,
  quantity integer,
  status text not null default 'active' check (status in ('active','past_due','canceled')),
  current_period_end timestamptz,
  source text not null check (source in ('stripe','master'))
);
create unique index if not exists uq_org_entitlements_org_kind_key
  on public.org_entitlements(organization_id, kind, key);

-- audit_log + audit_trigger_fn (la fn real solo usa id + to_jsonb, no organization_id).
create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid, actor_role text, action text, table_name text,
  record_id uuid, old_data jsonb, new_data jsonb,
  created_at timestamptz not null default now()
);
create or replace function public.audit_trigger_fn()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor uuid := auth.uid(); v_role text;
begin
  select role::text into v_role from public.profiles where id = v_actor;
  if (tg_op = 'INSERT') then
    insert into public.audit_log(actor_id, actor_role, action, table_name, record_id, new_data)
      values (v_actor, v_role, 'insert', tg_table_name, new.id, to_jsonb(new));
    return new;
  elsif (tg_op = 'UPDATE') then
    insert into public.audit_log(actor_id, actor_role, action, table_name, record_id, old_data, new_data)
      values (v_actor, v_role, 'update', tg_table_name, new.id, to_jsonb(old), to_jsonb(new));
    return new;
  elsif (tg_op = 'DELETE') then
    insert into public.audit_log(actor_id, actor_role, action, table_name, record_id, old_data)
      values (v_actor, v_role, 'delete', tg_table_name, old.id, to_jsonb(old));
    return old;
  end if;
  return null;
end $$;

-- Helpers de rol/centro (mismas firmas que las reales), SECURITY DEFINER, por GUC.
create or replace function public.is_master() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select 'master'::public.user_role = any(roles)
                   from public.profiles where id = auth.uid()), false);
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select 'admin'::public.user_role = any(roles)
                   from public.profiles where id = auth.uid()), false);
$$;
create or replace function public.current_organization_id() returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select organization_id from public.profiles where id = auth.uid();
$$;
-- current_staff_id(): 0076 lo usa en su write policy; no lo ejercitamos aquí → null.
create or replace function public.current_staff_id() returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select null::uuid;
$$;

-- Rol authenticated + grants: para EJERCER la RLS de verdad (postgres, dueño, la salta).
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
grant usage on schema public to authenticated;

-- Datos: un centro y un MIEMBRO (clínico) SIN protocol:author. Tiene otros derechos
-- (incluso el módulo de protocolos) para probar que NADA salvo protocol:author abre el
-- catálogo. UUIDs fijos para el test.
insert into public.organizations (id, name)
  values ('11111111-1111-1111-1111-111111111111', 'Centro sin author')
  on conflict do nothing;
insert into public.profiles (id, roles, role, organization_id)
  values ('22222222-2222-2222-2222-222222222222',   -- clínico (NO admin)
          array['clinico']::public.user_role[], 'clinico',
          '11111111-1111-1111-1111-111111111111'),
         ('33333333-3333-3333-3333-333333333333',   -- ADMIN del MISMO centro
          array['admin']::public.user_role[], 'admin',
          '11111111-1111-1111-1111-111111111111')
  on conflict do nothing;
-- Derechos que NO son protocol:author (para que el test sea honesto).
insert into public.org_entitlements (organization_id, kind, key, status, source)
  values ('11111111-1111-1111-1111-111111111111', 'module', 'admin', 'active', 'master'),
         ('11111111-1111-1111-1111-111111111111', 'module', 'insumos', 'active', 'master')
  on conflict do nothing;

-- Tres centros para la ASIMETRÍA DE VIGENCIA (test C): cada uno con un admin y su
-- protocol:author de distinto origen/fecha. current_org_has_protocol_author() se prueba
-- directo por auth.uid (no hace falta RLS): mira la vigencia, no la visibilidad de filas.
--   A (master, sin fecha)                       → ABRE
--   B (master, fecha VENCIDA)                   → CIERRA
--   C (stripe, fecha vencida, status activo)    → ABRE (Stripe ignora la fecha)
insert into public.organizations (id, name) values
  ('44444444-4444-4444-4444-444444444444', 'A master sin fecha'),
  ('55555555-5555-5555-5555-555555555555', 'B master vencido'),
  ('66666666-6666-6666-6666-666666666666', 'C stripe vencido')
  on conflict do nothing;
insert into public.profiles (id, roles, role, organization_id) values
  ('4a000000-0000-0000-0000-000000000000', array['admin']::public.user_role[], 'admin', '44444444-4444-4444-4444-444444444444'),
  -- Miembro del MISMO centro author pero SIN rol admin (clínico): capacidad del centro sí,
  -- autoridad del usuario no. Prueba que la autoridad única (6.2) pide rol, no solo derecho.
  ('4b000000-0000-0000-0000-000000000000', array['clinico']::public.user_role[], 'clinico', '44444444-4444-4444-4444-444444444444'),
  ('5a000000-0000-0000-0000-000000000000', array['admin']::public.user_role[], 'admin', '55555555-5555-5555-5555-555555555555'),
  ('6a000000-0000-0000-0000-000000000000', array['admin']::public.user_role[], 'admin', '66666666-6666-6666-6666-666666666666')
  on conflict do nothing;
insert into public.org_entitlements (organization_id, kind, key, status, source, current_period_end) values
  ('44444444-4444-4444-4444-444444444444', 'module', 'protocol:author', 'active', 'master', null),
  ('55555555-5555-5555-5555-555555555555', 'module', 'protocol:author', 'active', 'master', now() - interval '1 day'),
  ('66666666-6666-6666-6666-666666666666', 'module', 'protocol:author', 'active', 'stripe', now() - interval '1 day')
  on conflict do nothing;

-- module_settings + dos centros para el CAMBIO DE CONDUCTA de 1.5.b: encender un módulo
-- exige module:clinico VIGENTE. Antes (0121) miraba solo status; ahora respeta el
-- vencimiento (org_entitlement_vigente).
--   77 (prueba VENCIDA: clinico master, fecha pasada) → ya NO puede encender.
--   88 (vigente: clinico master, sin fecha)           → sí puede.
create table if not exists public.module_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  module_key text not null,
  enabled boolean not null default false
);
grant select, insert, update, delete on public.module_settings to authenticated;
insert into public.organizations (id, name) values
  ('77777777-7777-7777-7777-777777777777', 'Prueba VENCIDA (clinico master pasado)'),
  ('88888888-8888-8888-8888-888888888888', 'Vigente (clinico master sin fecha)')
  on conflict do nothing;
insert into public.org_entitlements (organization_id, kind, key, status, source, current_period_end) values
  ('77777777-7777-7777-7777-777777777777', 'module', 'clinico', 'active', 'master', now() - interval '1 day'),
  ('88888888-8888-8888-8888-888888888888', 'module', 'clinico', 'active', 'master', null)
  on conflict do nothing;

-- Centro que CONSUME el protocolo Kura+ (seat:protocolo vigente, cupo>=1) SIN protocol:author
-- (para el test 2.d: recibe su régimen del catálogo pero no puede LEER el catálogo). Con un
-- admin y un insumo en su inventario, al que apuntará la regla de catálogo del test.
insert into public.organizations (id, name) values
  ('99999999-9999-9999-9999-999999999999', 'Centro que CONSUME Kura+') on conflict do nothing;
insert into public.profiles (id, roles, role, organization_id) values
  ('9a000000-0000-0000-0000-000000000000', array['admin']::public.user_role[], 'admin', '99999999-9999-9999-9999-999999999999')
  on conflict do nothing;
insert into public.org_entitlements (organization_id, kind, key, quantity, status, source, current_period_end) values
  ('99999999-9999-9999-9999-999999999999', 'seat', 'protocolo', 1, 'active', 'master', null)
  on conflict do nothing;
insert into public.inventory_items (id, organization_id, site_id, name) values
  ('c0000000-0000-0000-0000-000000000001', '99999999-9999-9999-9999-999999999999', null, 'Apósito del consumidor')
  on conflict do nothing;
