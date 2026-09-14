-- =============================================================================
-- 0115_module_settings_requires_entitlement.sql — Candado de pago (Fase 1, §5).
-- =============================================================================
-- El admin del centro CONSERVA su capacidad de configurar: apagar lo que sí pagó
-- y volverlo a encender. Lo que deja de poder es ENCENDER lo que NO pagó.
--
-- El candado es un TRIGGER (no se toca la policy del 0041, para no perder la
-- configuración legítima): al insertar o actualizar una fila con enabled=true, si
-- el centro no tiene el derecho del módulo correspondiente, raise exception.
-- Excepción: el master. Apagar (enabled=false) siempre pasa.
--
-- Mapeo module_key → derecho (mismo AND de §4): insumos→module:insumos,
-- comercial→module:comercial, y el resto (patients, agenda, prevention, reports,
-- ekare, vac) → module:clinico (ekare entra con el clínico, sin costo).
--
-- Nombre trg_zz_* para correr AL FINAL (tras cualquier sync BEFORE), por la
-- convención de orden de triggers del repo.
-- =============================================================================

create or replace function public.enforce_module_requires_entitlement()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_required text;
  v_label text;
begin
  -- Apagar o dejar apagado: siempre permitido (config legítima, §5).
  if new.enabled is not true then
    return new;
  end if;

  -- El master no tiene candado (opera la plataforma).
  if public.is_master() then
    return new;
  end if;

  v_required := case new.module_key
                  when 'insumos' then 'insumos'
                  when 'comercial' then 'comercial'
                  else 'clinico'
                end;
  v_label := case v_required
               when 'insumos' then 'Insumos'
               when 'comercial' then 'Comercial'
               else 'Clínico'
             end;

  if not exists (
    select 1 from public.org_entitlements e
    where e.organization_id = new.organization_id
      and e.kind = 'module'
      and e.key = v_required
      and e.status = 'active'
  ) then
    raise exception 'El centro no tiene contratado el módulo %.', v_label;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_zz_enforce_module_requires_entitlement on public.module_settings;
create trigger trg_zz_enforce_module_requires_entitlement
  before insert or update on public.module_settings
  for each row execute function public.enforce_module_requires_entitlement();
