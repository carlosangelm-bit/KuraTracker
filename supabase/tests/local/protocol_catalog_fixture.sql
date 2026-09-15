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

-- inventory_items: solo lo que 0076 referencia por FK (inventory_item_id).
create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid()
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
  values ('22222222-2222-2222-2222-222222222222',
          array['clinico']::public.user_role[], 'clinico',
          '11111111-1111-1111-1111-111111111111')
  on conflict do nothing;
-- Derechos que NO son protocol:author (para que el test sea honesto).
insert into public.org_entitlements (organization_id, kind, key, status, source)
  values ('11111111-1111-1111-1111-111111111111', 'module', 'admin', 'active', 'master'),
         ('11111111-1111-1111-1111-111111111111', 'module', 'insumos', 'active', 'master')
  on conflict do nothing;
