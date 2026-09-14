-- =============================================================================
-- 0120_free_plan_cap_yields_to_paid.sql — El tope de 5 pacientes del plan gratuito
-- CEDE ante un derecho de Stripe activo (verificación de fase 2).
-- =============================================================================
-- plan:gratuito se escribe una vez, al crear el centro, con source='master', y NADA
-- lo quita: el barrido de apply_stripe_subscription_event solo toca source='stripe'
-- (a propósito, para que un regalo del master sobreviva la renovación). Así que la
-- fila del plan gratuito sigue 'active' aunque el centro contrate — y el tope de
-- 0118 la miraba y seguía mordiendo: un centro que YA pagó no podía dar de alta al
-- 6º paciente, con el mensaje de "contrata un plan" a alguien que acaba de hacerlo.
--
-- Arreglo por PREDICADO (no por bandera): el tope no muerde si el centro tiene algún
-- derecho de Stripe activo. Se deriva del hecho de pago, no de acordarse de bajar
-- una bandera, y se corrige en ambos sentidos: si deja de pagar, sus derechos pasan
-- a past_due y el tope VUELVE — sin borrar pacientes (el trigger es de alta y
-- reactivación, no toca los que ya están). No toca el invariante de que el webhook
-- nunca escribe source='master'. Redefine la función; el trigger (0118) no cambia.
-- =============================================================================

create or replace function public.assert_free_plan_patient_cap()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
begin
  -- Solo interesa cuando el paciente QUEDA activo y antes no lo estaba.
  if new.is_active is not true then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.is_active is true then
    return new;
  end if;

  -- No es plan gratuito activo → sin tope aquí.
  if not exists (
    select 1 from public.org_entitlements e
    where e.organization_id = new.organization_id
      and e.kind = 'plan' and e.key = 'gratuito' and e.status = 'active'
  ) then
    return new;
  end if;

  -- Paga: cualquier derecho vigente de Stripe supera al plan gratuito residual.
  if exists (
    select 1 from public.org_entitlements e
    where e.organization_id = new.organization_id
      and e.source = 'stripe' and e.status = 'active'
  ) then
    return new;
  end if;

  -- Cuenta los OTROS activos (en reactivación este aún está inactivo en la tabla).
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
