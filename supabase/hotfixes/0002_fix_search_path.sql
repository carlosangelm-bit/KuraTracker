-- =============================================================================
-- KuraTracker - HOTFIX: search_path faltante en funciones SECURITY DEFINER
-- =============================================================================
-- Aplica sobre un proyecto donde YA se corrio 0001->0004 (como el piloto).
-- Seguro de re-ejecutar: solo usa CREATE OR REPLACE FUNCTION (no toca ningun
-- trigger existente, no crea tablas, no borra nada).
--
-- BUG ORIGINAL (reportado y corregido en vivo durante el piloto):
--   Al crear un usuario en Authentication -> Add user, Supabase mostraba
--   "Database error creating new user". En los Postgres logs el error real
--   era: type "user_role" does not exist.
--
-- CAUSA:
--   public.handle_new_auth_user() (trigger AFTER INSERT ON auth.users) hace
--   el cast (new.raw_user_meta_data->>'role')::user_role SIN calificar el
--   esquema. Ese trigger lo dispara el rol interno "supabase_auth_admin" al
--   crear la fila en auth.users, y ese rol NO tiene "public" en su
--   search_path por defecto -> Postgres no encuentra el tipo "user_role"
--   (que si existe, pero como public.user_role).
--
--   El mismo patron de riesgo (tipo/objeto sin calificar dentro de una
--   funcion SECURITY DEFINER, sin search_path fijo) tambien estaba presente
--   en current_user_role(), is_admin() y current_staff_id() -- no fallaban
--   hoy porque se ejecutan desde contextos (SQL Editor, RLS invocado por
--   "authenticated") que si tienen "public" en su search_path, pero es el
--   mismo defecto latente. Se corrigen las 5 funciones SECURITY DEFINER del
--   archivo por consistencia y para no reintroducir el bug en el futuro.
--
-- FIX: agregar "set search_path = public, pg_temp" a cada funcion y
-- calificar por esquema los tipos referenciados en el cuerpo
-- (::public.user_role en vez de ::user_role).
--
-- Este mismo fix ya esta incorporado en
-- supabase/migrations/0002_triggers_and_functions.sql para que un proyecto
-- NUEVO que corra las migraciones desde cero no sufra este bug. Este archivo
-- es solo para aplicar el fix a un proyecto EXISTENTE sin tener que
-- re-correr toda la migracion 0002 (que fallaria con "trigger already
-- exists" por los triggers ya creados).
-- =============================================================================

create or replace function public.audit_trigger_fn()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_role text;
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
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, role, full_name, email)
  values (
    new.id,
    coalesce((new.raw_user_meta_data->>'role')::public.user_role, 'clinico'::public.user_role),
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.current_user_role()
returns public.user_role language sql stable security definer
set search_path = public, pg_temp
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((select role = 'admin'::public.user_role from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.current_staff_id()
returns uuid language sql stable security definer
set search_path = public, pg_temp
as $$
  select id from public.staff where profile_id = auth.uid();
$$;

-- -----------------------------------------------------------------------------
-- Verificacion rapida post-hotfix (opcional, solo lectura):
-- -----------------------------------------------------------------------------
-- select proname, prosecdef, proconfig
-- from pg_proc
-- where pronamespace = 'public'::regnamespace
--   and proname in ('audit_trigger_fn','handle_new_auth_user',
--                    'current_user_role','is_admin','current_staff_id');
-- La columna "proconfig" debe mostrar algo como
-- {search_path=public,pg_temp} para las 5 funciones.
-- =============================================================================
