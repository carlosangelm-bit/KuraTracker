-- =============================================================================
-- KuraTracker - Volumen por Kundin (editable) + flag de ajuste manual
-- =============================================================================
-- Contexto (tarea "calculo de volumen (Kundin) editable + graficas de
-- volumen y composicion de tejido", rama feat/volume-kundin-charts):
-- volume_cm3 (wound_measurements, migracion 0008) ya existia como campo de
-- medicion 3D para heridas profundas, pero se llenaba 100% a mano en
-- seguimiento y ni siquiera existia en la UI de valoracion. Ahora ambas
-- pantallas (wound_capture_screen.dart / follow_up_capture_screen.dart)
-- auto-calculan volume_cm3 con la formula de Kundin
-- (V = Largo x Ancho x Profundidad x 0.327) cada vez que cambian las
-- medidas, pero el campo sigue siendo editable por el clinico.
--
-- volume_manual es un flag DERIVADO (no un toggle que el clinico marque):
-- el cliente compara el valor guardado en volume_cm3 contra el auto-calculo
-- de Kundin para las mismas medidas (con una tolerancia de 0.01 cm3 para
-- evitar falsos positivos por redondeo) y guarda true si el clinico
-- sobrescribio el valor a mano. Se usa para mostrar la anotacion
-- "✎ Volumen ajustado manualmente" en la UI de captura, en el detalle de
-- consulta de solo lectura y en el tooltip de la grafica de volumen del
-- dashboard de seguimiento.
--
-- Migracion ADITIVA e IDEMPOTENTE: solo agrega una columna boolean con
-- default false (nunca null), sin backfill adicional (las filas existentes
-- quedan en false = "no hay evidencia de ajuste manual", lo cual es
-- correcto porque volume_cm3 nunca se auto-calculo antes de esta tarea).
-- No crea ninguna tabla ni politica nueva; no toca RLS existente.
--
-- IMPORTANTE (orden de despliegue, igual que 0013/0014): el codigo de la
-- rama feat/volume-kundin-charts lee y escribe volume_manual en
-- wound_measurements. Sin esta columna en Supabase, el guardado de
-- cualquier valoracion o seguimiento con herida profunda fallaria. Por eso
-- esta migracion debe aplicarse ANTES del rebuild de produccion.
-- =============================================================================

alter table public.wound_measurements
  add column if not exists volume_manual boolean not null default false;

comment on column public.wound_measurements.volume_manual is
  'true si el clinico sobrescribio a mano el volumen auto-calculado por Kundin (V = Largo x Ancho x Profundidad x 0.327) para esta medicion. Se deriva comparando volume_cm3 contra el auto-calculo al momento de guardar (tolerancia 0.01 cm3), no es un toggle manual persistido por el usuario.';
