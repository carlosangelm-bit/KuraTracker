-- =============================================================================
-- KuraTracker - Triggers y funciones auxiliares
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Folios automaticos: PA{YYYY}-NNNN para pacientes, K{YYYY}-NNNN para staff.
-- El usuario puede sobreescribir el folio manualmente (p.ej. para mantener
-- folios historicos EXP2025-XXXX importados de eKare); solo se autogenera
-- si el folio llega NULL o vacio al insertar.
-- -----------------------------------------------------------------------------

create sequence if not exists public.patient_folio_seq;

create or replace function public.generate_patient_folio()
returns trigger language plpgsql as $$
declare
  yr text := to_char(now(), 'YYYY');
  next_val bigint;
begin
  if new.folio is null or new.folio = '' then
    next_val := nextval('public.patient_folio_seq');
    new.folio := 'PA' || yr || '-' || lpad(next_val::text, 4, '0');
  end if;
  return new;
end;
$$;

create trigger trg_patients_folio
  before insert on public.patients
  for each row execute function public.generate_patient_folio();

create or replace function public.generate_staff_folio()
returns trigger language plpgsql as $$
declare
  yr text := to_char(now(), 'YYYY');
  next_val bigint;
begin
  if new.folio is null or new.folio = '' then
    next_val := nextval('public.staff_folio_seq');
    new.folio := 'K' || yr || '-' || lpad(next_val::text, 4, '0');
  end if;
  return new;
end;
$$;

create trigger trg_staff_folio
  before insert on public.staff
  for each row execute function public.generate_staff_folio();

-- -----------------------------------------------------------------------------
-- updated_at automatico
-- -----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger trg_patients_updated_at before update on public.patients
  for each row execute function public.set_updated_at();
create trigger trg_consultations_updated_at before update on public.consultations
  for each row execute function public.set_updated_at();
create trigger trg_wounds_updated_at before update on public.wounds
  for each row execute function public.set_updated_at();
create trigger trg_treatment_plans_updated_at before update on public.treatment_plans
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Bitacora de auditoria generica (AFTER INSERT/UPDATE/DELETE)
-- -----------------------------------------------------------------------------

create or replace function public.audit_trigger_fn()
returns trigger language plpgsql security definer as $$
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

-- Se audita todo lo clinicamente sensible.
create trigger trg_audit_patients
  after insert or update or delete on public.patients
  for each row execute function public.audit_trigger_fn();
create trigger trg_audit_wounds
  after insert or update or delete on public.wounds
  for each row execute function public.audit_trigger_fn();
create trigger trg_audit_consultations
  after insert or update or delete on public.consultations
  for each row execute function public.audit_trigger_fn();
create trigger trg_audit_measurements
  after insert or update or delete on public.wound_measurements
  for each row execute function public.audit_trigger_fn();
create trigger trg_audit_treatment_plans
  after insert or update or delete on public.treatment_plans
  for each row execute function public.audit_trigger_fn();
create trigger trg_audit_kura_recommendations
  after insert or update or delete on public.kura_recommendations
  for each row execute function public.audit_trigger_fn();
create trigger trg_audit_staff
  after insert or update or delete on public.staff
  for each row execute function public.audit_trigger_fn();
create trigger trg_audit_profiles
  after insert or update or delete on public.profiles
  for each row execute function public.audit_trigger_fn();

-- -----------------------------------------------------------------------------
-- Helper: crear perfil automaticamente al registrar un usuario en auth.users
-- -----------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, role, full_name, email)
  values (
    new.id,
    coalesce((new.raw_user_meta_data->>'role')::user_role, 'clinico'),
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- -----------------------------------------------------------------------------
-- Helper functions usadas por RLS (evitan recursion / simplifican policies)
-- -----------------------------------------------------------------------------

create or replace function public.current_user_role()
returns user_role language sql stable security definer as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.current_staff_id()
returns uuid language sql stable security definer as $$
  select id from public.staff where profile_id = auth.uid();
$$;
