-- =============================================================================
-- 0073_patient_labs_clinical_domain.sql — Dominio clínico completo de labs
-- =============================================================================
-- María amplió el módulo de laboratorios al DOMINIO CLÍNICO completo: cada
-- parámetro se puntúa 0–3 según rangos (nutrición, metabólico, hematología,
-- coagulación, inflamación). 0070 ya trae glucosa, HbA1c, albúmina, hemoglobina
-- y SatO₂; aquí se agregan los 6 parámetros faltantes de su tabla.
--
-- El puntaje 0–3 se calcula en la app (umbrales en config de código, en
-- validación clínica); NO se persiste (se recomputa desde el valor crudo).
--
-- Solo agrega columnas nullable; NO toca RLS (las policies de patient_labs de
-- 0070 ya cubren las columnas nuevas).
-- =============================================================================

alter table public.patient_labs
  add column if not exists prealbumin_mg_dl numeric(6, 1),   -- Prealbúmina (mg/dL)
  add column if not exists total_protein_g_dl numeric(4, 1), -- Proteínas totales (g/dL)
  add column if not exists crp_mg_l numeric(7, 1),           -- PCR / inflamación (mg/L)
  add column if not exists pt_seconds numeric(5, 1),         -- TP (tiempo de protrombina, seg)
  add column if not exists hematocrit_pct numeric(4, 1),     -- Hematocrito (%)
  add column if not exists platelets_ul numeric(9, 0),       -- Plaquetas (µL, conteo absoluto)
  add column if not exists ptt_seconds numeric(5, 1);        -- TPP (tiempo de tromboplastina parcial, seg)

comment on column public.patient_labs.prealbumin_mg_dl is
  'Prealbúmina (mg/dL). Marcador nutricional de vida media corta; opcional si no se dispone.';
comment on column public.patient_labs.crp_mg_l is
  'Proteína C reactiva (mg/L). Inflamación; con inflamación marcada interpretar albúmina con cautela.';
comment on column public.patient_labs.pt_seconds is
  'Tiempo de protrombina (seg). Riesgo de sangrado ante procedimientos invasivos (p. ej. desbridamiento).';
comment on column public.patient_labs.ptt_seconds is
  'Tiempo de tromboplastina parcial (seg). Sospecha de coagulopatía.';
