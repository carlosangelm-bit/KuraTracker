-- =============================================================================
-- 0126_retire_free_plan.sql — Retira el plan gratuito con tope de 5 pacientes.
-- La prueba de 30 días (create_trial_organization, 0125) lo reemplaza.
-- =============================================================================
-- Salida C (Carlos, 12-sep): NADA que migrar en producción — org_entitlements y el
-- modelo de licencia (0113-0126) viven solo en staging; main sigue en 0107. Es una
-- operación enteramente de staging.
--
-- 1) create_organization_with_admin (nacimiento del plan gratuito) queda como puerta
--    CERRADA que apunta a create_trial_organization. No se BORRA —romper una función
--    referenciada por comentarios/historia es peor que dejarla inerte— pero se le
--    revoca execute a authenticated para que nadie la alcance.
-- 2) El trigger + función del tope de pacientes se ELIMINAN: sin plan gratuito no hay
--    tope; la prueba vencida cae en solo lectura por tiempo (canWriteModule), no por
--    conteo de pacientes.
-- =============================================================================

-- 1. Puerta cerrada. Misma firma que 0116; el cuerpo solo rebota.
create or replace function public.create_organization_with_admin(
  p_organization_name text,
  p_admin_full_name text,
  p_admin_is_clinical boolean default false
)
returns uuid language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  raise exception
    'create_organization_with_admin fue retirada (plan gratuito). Usa create_trial_organization.';
end;
$$;

revoke execute on function public.create_organization_with_admin(text, text, boolean)
  from authenticated;

-- 2. Tope de pacientes del plan gratuito: fuera (trigger + función).
drop trigger if exists trg_zz_free_plan_patient_cap on public.patients;
drop function if exists public.assert_free_plan_patient_cap();
