-- Lo que create_trial_organization (0135) necesita más allá de lo que trae el fixture
-- de 0132: columnas de organizations y las tablas del fundador opcional (aunque se
-- llame con p_founder=null, se crean por robustez).
alter table public.organizations
  add column if not exists center_type text not null default 'clinica_heridas',
  add column if not exists is_active boolean not null default true,
  add column if not exists is_test boolean not null default false;
create table if not exists public.user_center_memberships (
  profile_id uuid, organization_id uuid, roles public.user_role[],
  is_active boolean not null default true, unique (profile_id, organization_id));
create table if not exists public.staff (
  id uuid primary key default gen_random_uuid(), profile_id uuid, folio text,
  full_name text, role_title text, organization_id uuid);
insert into public.profiles (id, roles, role) values
  ('99999999-9999-9999-9999-999999999999', array['master']::public.user_role[], 'master')
  on conflict (id) do nothing;
