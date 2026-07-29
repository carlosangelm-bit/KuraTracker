-- =============================================================================
-- 0061_realtime_payments.sql — Habilita Supabase Realtime para pagos/cobros
-- =============================================================================
-- El módulo Comercial (Cobros / Conciliación) se suscribe por Realtime a estas
-- tablas para reflejar un pago en cuanto el webhook (Stripe/MP) lo registra, sin
-- que el usuario tenga que refrescar la página.
--
-- Realtime entrega eventos solo de tablas incluidas en la publicación
-- `supabase_realtime`. Además, para que los eventos UPDATE/DELETE incluyan las
-- columnas que usa la RLS (organization_id) al filtrar por usuario, la tabla
-- necesita REPLICA IDENTITY FULL.
--
-- Idempotente: sólo agrega la tabla a la publicación si aún no está.
-- =============================================================================

alter table public.charges replica identity full;
alter table public.point_payments replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'charges'
  ) then
    alter publication supabase_realtime add table public.charges;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'point_payments'
  ) then
    alter publication supabase_realtime add table public.point_payments;
  end if;
end $$;
