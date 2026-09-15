-- Fixture MÍNIMO para 0134_prevent_site_deactivation.sql: solo las tres tablas que el
-- trigger toca/lee (sites, staff, inventory_movements) con las columnas que consulta.
-- No necesita el stack de Supabase ni la cadena completa de migraciones.
create extension if not exists pgcrypto;

create schema if not exists public;

create table public.sites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  is_active boolean not null default true
);

create table public.staff (
  id uuid primary key default gen_random_uuid(),
  primary_site_id uuid,
  is_active boolean not null default true
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null,
  inventory_item_id uuid not null,
  delta integer not null
);
