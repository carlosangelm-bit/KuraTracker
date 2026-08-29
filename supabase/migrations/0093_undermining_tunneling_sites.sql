-- =============================================================================
-- 0093_undermining_tunneling_sites.sql — Dirección de socavamiento/tunelización
-- =============================================================================
-- La tunelización es un PUNTO (un trayecto que sale en una dirección: "a las 7,
-- 4 cm"). El socavamiento es un ARCO (despegue del borde a lo largo de un tramo:
-- "de las 2 a las 5, 3 cm"). Modelar el socavamiento con una sola hora le
-- quitaría la extensión, que es justo lo que el clínico mide para ver si crece o
-- cede entre visitas. Por eso son estructuras distintas.
--
-- Se CONSERVAN los booleanos `tunneling`/`undermining`: el booleano dice si hay,
-- el arreglo dice dónde y cuánto. Histórico tiene solo el booleano; un arreglo
-- vacío con el booleano en true = "hay, no se detalló" (así se lee en el reporte).
--
-- Referencia del reloj: las 12 = la CABEZA del paciente (va en el comentario y en
-- la etiqueta de captura, para que dos clínicos no capturen sistemas distintos).
-- El arco PUEDE cruzar las 12 (de 11 a 2 es válido): no se valida from < to; se
-- valida reloj 1–12 y profundidad > 0 (en la app).
-- =============================================================================

alter table public.wound_measurements
  add column if not exists tunneling_sites jsonb not null default '[]'::jsonb;

alter table public.wound_measurements
  add column if not exists undermining_sites jsonb not null default '[]'::jsonb;

comment on column public.wound_measurements.tunneling_sites is
  'Trayectos de tunelización: [{"clock":7,"depth_cm":4.0}]. Reloj 1–12 con las 12 en la cabeza del paciente. El booleano tunneling dice si hay; arreglo vacío con tunneling=true = "hay, no se detalló".';

comment on column public.wound_measurements.undermining_sites is
  'Arcos de socavamiento: [{"clock_from":2,"clock_to":5,"depth_cm":3.0}]. Reloj 1–12 (12 = cabeza del paciente); el arco puede cruzar las 12 (11→2). El booleano undermining dice si hay; arreglo vacío con undermining=true = "hay, no se detalló".';
