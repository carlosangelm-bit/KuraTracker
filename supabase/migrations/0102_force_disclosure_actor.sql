-- =============================================================================
-- 0102_force_disclosure_actor.sql — El actor de una divulgación lo IMPONE el
-- servidor, no el cliente.
-- =============================================================================
-- 0101 dejó las filas inmutables DESPUÉS del insert, pero el CONTENIDO del
-- insert (actor_id / actor_email) era palabra del cliente: un miembro del
-- centro podía registrar una exportación atribuida a un colega. En un registro
-- cuyo propósito es "quién se llevó los datos", un actor falsificable es peor
-- que no tenerlo (se ve autoritativo y no lo es).
--
-- Este trigger BEFORE INSERT sobreescribe actor_id/actor_email con el usuario
-- autenticado real (auth.uid() + su email del perfil), ignorando lo que mande
-- el cliente. La app puede seguir mandándolos; se ignoran. No rompe nada.
--
-- Alcance (no cambia): endurece la ATRIBUCIÓN de los registros que sí se
-- escriben; NO hace inevitable la escritura (sigue siendo un registro de uso
-- legítimo). Omitir el insert es distinto de dejar un rastro falso; lo segundo
-- se cierra aquí.
-- =============================================================================

create or replace function public.force_disclosure_actor()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  new.actor_id := auth.uid();
  new.actor_email := coalesce(
    (select email from public.profiles where id = auth.uid()),
    new.actor_email);          -- fallback: no perder el dato si no hay perfil
  return new;
end; $$;

drop trigger if exists trg_force_disclosure_actor on public.data_disclosures;
create trigger trg_force_disclosure_actor
  before insert on public.data_disclosures
  for each row execute function public.force_disclosure_actor();
