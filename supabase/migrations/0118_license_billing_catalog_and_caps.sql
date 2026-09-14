-- =============================================================================
-- 0118_license_billing_catalog_and_caps.sql — Fase 2 (cobro de suscripciones):
-- siembra del catálogo por clave de búsqueda, customer de Stripe por centro, y el
-- tope de pacientes del plan gratuito que faltaba en el servidor.
-- =============================================================================
-- Depende de 0113 (billing_catalog con lookup_key, org_entitlements) y 0116
-- (consumes_clinical_seat, assert_seat_available). No toca el motor de visión.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. billing_catalog — siembra (§1). IGUAL en sandbox y producción: la identidad
--    es la clave de búsqueda, no el price_id (ese difiere por entorno y queda
--    informativo/null aquí). Idempotente por on-conflict, para poder re-sembrar.
--    Las diez tarifas ya existen en Stripe con estas claves (IVA incluido).
-- -----------------------------------------------------------------------------
insert into public.billing_catalog (lookup_key, kind, key, interval, unit) values
  ('clinico_mensual',   'seat',   'clinico',   'month', 'seat'),
  ('clinico_anual',     'seat',   'clinico',   'year',  'seat'),
  ('protocolo_mensual', 'seat',   'protocolo', 'month', 'seat'),
  ('protocolo_anual',   'seat',   'protocolo', 'year',  'seat'),
  ('admin_mensual',     'module', 'admin',     'month', 'center'),
  ('admin_anual',       'module', 'admin',     'year',  'center'),
  ('insumos_mensual',   'module', 'insumos',   'month', 'center'),
  ('insumos_anual',     'module', 'insumos',   'year',  'center'),
  ('comercial_mensual', 'module', 'comercial', 'month', 'center'),
  ('comercial_anual',   'module', 'comercial', 'year',  'center')
on conflict (lookup_key) do update set
  kind = excluded.kind,
  key = excluded.key,
  interval = excluded.interval,
  unit = excluded.unit;

-- -----------------------------------------------------------------------------
-- 2. organizations.stripe_customer_id (§3.10) — un centro, un customer, una
--    suscripción. license-checkout lo reutiliza si existe y lo crea si no.
-- -----------------------------------------------------------------------------
alter table public.organizations add column if not exists stripe_customer_id text;
comment on column public.organizations.stripe_customer_id is
  'Customer de Stripe del centro (suscripción de licencia). Uno por centro; lo '
  'escribe license-checkout (service_role). null hasta la primera compra.';

-- La suscripción VIVA del centro (una sola). license-checkout la lee: si existe,
-- la SEGUNDA compra ACTUALIZA esa suscripción (prorrateo) en vez de crear otra;
-- si es null, crea una. apply_stripe_subscription_event la fija al activarse y la
-- pone en null al cancelarse (atómico con los derechos).
alter table public.organizations add column if not exists stripe_subscription_id text;
comment on column public.organizations.stripe_subscription_id is
  'Suscripción de licencia viva del centro (o null). La mantiene el webhook vía '
  'apply_stripe_subscription_event. license-checkout enruta a actualizar vs crear.';

-- -----------------------------------------------------------------------------
-- 3. Tope de pacientes del plan gratuito (§6) — hasta ahora solo existía en el
--    cliente (kFreePlanPatientCap=5 en license_summary.dart) y nada en el servidor
--    lo aplicaba: con el token del centro se podía insertar el paciente 6 por la
--    API. Este trigger lo impone en la base. Solo muerde si el centro tiene
--    plan:gratuito ACTIVO; los planes de pago no tienen tope de pacientes aquí.
--    Cuenta pacientes ACTIVOS (los archivados no ocupan lugar).
--    Dispara en INSERT y en la REACTIVACIÓN (is_active false→true): sin lo segundo,
--    la receta para saltarlo es archivar uno, dar de alta otro (vuelve a 5) y
--    reactivar el archivado → 6 activos, porque reactivar es un UPDATE que el
--    trigger de solo-insert no veía.
--    Excepción con prefijo estable (FREE_PLAN_PATIENT_CAP:) para que la app la
--    traduzca a la invitación a contratar. trg_zz_* para correr al final.
-- -----------------------------------------------------------------------------
create or replace function public.assert_free_plan_patient_cap()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
begin
  -- Solo interesa cuando el paciente QUEDA activo y antes no lo estaba: alta nueva
  -- activa, o reactivación. Un alta archivada, o un UPDATE que no lo activa desde
  -- inactivo (ya estaba contado), no topan.
  if new.is_active is not true then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.is_active is true then
    return new;
  end if;

  if not exists (
    select 1 from public.org_entitlements e
    where e.organization_id = new.organization_id
      and e.kind = 'plan' and e.key = 'gratuito' and e.status = 'active'
  ) then
    return new;  -- no es plan gratuito → sin tope aquí.
  end if;

  -- Cuenta los OTROS activos (en reactivación, este aún está inactivo en la tabla;
  -- el id <> new.id lo deja explícito y es inocuo en el INSERT).
  select count(*) into v_count
  from public.patients p
  where p.organization_id = new.organization_id and p.is_active and p.id <> new.id;

  if v_count >= 5 then
    raise exception
      'FREE_PLAN_PATIENT_CAP: el plan gratuito permite 5 pacientes; contrata un plan para agregar más.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_zz_free_plan_patient_cap on public.patients;
create trigger trg_zz_free_plan_patient_cap
  before insert or update on public.patients
  for each row execute function public.assert_free_plan_patient_cap();
