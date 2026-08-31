-- =============================================================================
-- 0097_consultation_immutability.sql — Una consulta FINALIZADA es inmutable
-- =============================================================================
-- Hueco: `consultations_write` (0003) es `for all` sin condición de estado, así
-- que cualquier staff asignado o admin puede UPDATE/DELETE una consulta ya
-- finalizada (nota clínica firmada). La pantalla de captura de seguimiento,
-- alcanzable por URL con el id de una consulta cerrada, borra fotos/valoraciones/
-- mediciones y las reescribe con NUEVA firma y fecha — evidencia destruida y
-- sustituida sin rastro visible.
--
-- No se toca `consultations_write` (la convención de RLS es ADITIVA y, además,
-- las políticas permisivas se OR-ean: una nueva solo AMPLÍA, nunca restringe).
-- La restricción va por TRIGGER, mismo patrón que 0006 para profiles.
--
-- Regla: bloquear UPDATE/DELETE si la fila EXISTENTE (OLD) ya está finalizada
-- (is_draft = false). Preserva todo lo legítimo:
--   - editar un borrador           → OLD.is_draft = true  → pasa
--   - FINALIZAR un borrador        → OLD (previa) = draft  → pasa (transición)
--   - eliminar un borrador         → OLD.is_draft = true  → pasa
--   - crear consulta ya finalizada → es INSERT             → pasa
--   - sobrescribir nota firmada    → OLD.is_draft = false  → BLOQUEADO
--
-- La corrección clínica NO se cierra: va por notas de enmienda
-- (clinical_amendments, append-only, insert en otra tabla → no la toca este
-- trigger). Bloquea también UPDATE directo por SQL (is_draft not null, 0001).
-- Una migración futura que deba tocar consultas finalizadas debe deshabilitar
-- temporalmente este trigger.
-- =============================================================================

create or replace function public.prevent_finalized_consultation_change()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.is_draft = false then
    raise exception
      'Consulta finalizada: es inmutable. Usa una nota de enmienda para corregir.';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_prevent_finalized_consultation_change on public.consultations;
create trigger trg_prevent_finalized_consultation_change
  before update or delete on public.consultations
  for each row execute function public.prevent_finalized_consultation_change();
