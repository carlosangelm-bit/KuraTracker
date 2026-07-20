-- 0022_org_acuity_credentials.sql
--
-- Agenda multi-centro, Fase 2: cada organización puede conectar SU propia cuenta
-- de Acuity (User ID + API Key), en vez de la cuenta única global (secrets).
--
-- Seguridad de la API Key:
--   - La tabla NO tiene policies para el cliente => ningún usuario (ni admin)
--     puede leer ni escribir la fila directamente por PostgREST/RLS. Solo la
--     tocan el service role (Edge Functions) y los RPCs security-definer de
--     abajo, que validan rol/centro y NUNCA devuelven la key completa.
--   - Hardening futuro sugerido: cifrar acuity_api_key con Supabase Vault
--     (pgsodium) en vez de texto plano.

create table if not exists public.organization_acuity_credentials (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  acuity_user_id text not null,
  acuity_api_key text not null,
  active boolean not null default true,
  webhooks_registered boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

-- RLS habilitada SIN policies => acceso denegado a todo cliente autenticado.
-- El service role (Edge Functions) ignora RLS; los RPCs de abajo son la única
-- vía del cliente (y jamás exponen la key).
alter table public.organization_acuity_credentials enable row level security;

comment on table public.organization_acuity_credentials is
  'Credenciales de Acuity por organización (Fase 2 de agenda multi-centro). '
  'Sin policies de cliente a propósito: solo service role (Edge Functions) y los '
  'RPCs set_org_acuity_credentials / get_org_acuity_status (security definer) la '
  'tocan; la API key nunca se devuelve al cliente.';

-- Guardar/actualizar credenciales del centro (admin del propio centro o master).
-- Al cambiar la key se marca webhooks_registered=false (hay que re-registrar).
create or replace function public.set_org_acuity_credentials(
  p_org uuid, p_user_id text, p_api_key text
) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if coalesce(trim(p_user_id), '') = '' or coalesce(trim(p_api_key), '') = '' then
    raise exception 'User ID y API Key son obligatorios.';
  end if;
  if not (public.is_master() or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado para configurar Acuity en este centro.';
  end if;
  insert into public.organization_acuity_credentials
    (organization_id, acuity_user_id, acuity_api_key, active, webhooks_registered, updated_at, updated_by)
  values (p_org, trim(p_user_id), trim(p_api_key), true, false, now(), auth.uid())
  on conflict (organization_id) do update
    set acuity_user_id = excluded.acuity_user_id,
        acuity_api_key = excluded.acuity_api_key,
        active = true,
        webhooks_registered = false,
        updated_at = now(),
        updated_by = auth.uid();
end;
$$;

grant execute on function public.set_org_acuity_credentials(uuid, text, text) to authenticated;

-- Estado de la conexión SIN exponer la key completa (solo si está configurada,
-- el user id, los últimos 4 de la key y si los webhooks quedaron registrados).
-- Devuelve 0 filas si el centro no tiene credenciales.
create or replace function public.get_org_acuity_status(p_org uuid)
returns table(user_id text, key_last4 text, webhooks_registered boolean)
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not (public.is_master() or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado.';
  end if;
  return query
    select c.acuity_user_id, right(c.acuity_api_key, 4), c.webhooks_registered
    from public.organization_acuity_credentials c
    where c.organization_id = p_org and c.active;
end;
$$;

grant execute on function public.get_org_acuity_status(uuid) to authenticated;

-- Marca los webhooks como registrados (lo llama el flujo de configuración tras
-- registrarlos en Acuity). Mismo control de rol/centro.
create or replace function public.mark_org_acuity_webhooks(p_org uuid, p_registered boolean)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not (public.is_master() or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado.';
  end if;
  update public.organization_acuity_credentials
    set webhooks_registered = p_registered, updated_at = now()
    where organization_id = p_org;
end;
$$;

grant execute on function public.mark_org_acuity_webhooks(uuid, boolean) to authenticated;
