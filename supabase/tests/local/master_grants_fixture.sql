-- Fixture MÍNIMO para ejercitar el código REAL de 0132 (columnas, backfill, CHECK,
-- log, RPCs) sin la cadena completa de migraciones ni el stack de Supabase. Recrea
-- solo lo que 0132 toca/referencia, con las MISMAS firmas.
create extension if not exists pgcrypto;

-- auth.uid() de Supabase, stub: lee un GUC de prueba.
create schema if not exists auth;
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('test.uid', true), '')::uuid
$$;

-- enum de roles (0001-ish).
do $$ begin
  create type public.user_role as enum ('admin','clinico','master','cuidador','enfermeria');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  roles public.user_role[] not null default '{}',
  role public.user_role,
  is_active boolean not null default true
);

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null
);

-- is_master() idéntico a 0096.
create or replace function public.is_master()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((select 'master'::public.user_role = any(roles)
                   from public.profiles where id = auth.uid()), false);
$$;

-- org_entitlements con la forma de 0113 (lo que 0132 extiende).
create table if not exists public.org_entitlements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  kind text not null check (kind in ('plan','module','seat')),
  key text not null,
  quantity integer,
  constraint ent_quantity_shape check (
    (kind = 'seat' and quantity is not null and quantity >= 0)
    or (kind <> 'seat' and quantity is null)
  ),
  status text not null default 'active' check (status in ('active','past_due','canceled')),
  current_period_end timestamptz,
  source text not null check (source in ('stripe','master'))
);
create unique index if not exists uq_org_entitlements_org_kind_key
  on public.org_entitlements(organization_id, kind, key);

-- consumed_seat_demand(uuid): stub controlable por GUC (el real vive en 0128 y
-- tiene su propia prueba; aquí solo se ejercita la guardia 3 de la RPC).
create or replace function public.consumed_seat_demand(p_org uuid)
returns int language sql stable
set search_path = public, pg_temp
as $$
  select coalesce(nullif(current_setting('test.demand', true), '')::int, 0)
$$;
