-- Limpieza única del espejo local de citas de Acuity.
--
-- Contexto: el backfill inicial importó ~2200 citas (todo el histórico, incluidos
-- Kuradores inactivos/no mapeados). Ya acotamos backfill y webhook para guardar
-- SOLO las citas de Kuradores activos mapeados; este script vacía el espejo para
-- re-importar limpio.
--
-- Vaciar la tabla es SEGURO: Acuity es la fuente de verdad; el backfill acotado
-- la vuelve a poblar únicamente con las citas vigentes.
--
-- Orden de ejecución (para que no se re-importe la basura):
--   1) Corregir el mapeo (mapear a María, desmapear/desactivar a Alpizar) — Genspark.
--   2) Deploy de acuity-backfill y acuity-webhook (--no-verify-jwt) acotadas.
--   3) Correr ESTE script (delete).
--   4) Re-correr el backfill -> debe quedar un puñado de citas (María + Juan Carlos).
--   5) Verificar:  select count(*), staff_id from public.appointments group by staff_id;

delete from public.appointments;
