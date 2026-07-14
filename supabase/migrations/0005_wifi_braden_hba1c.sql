-- =============================================================================
-- KuraTracker - Campos faltantes vs. Hoja de Valoracion de Ingreso Kura+
-- =============================================================================
-- Prioridad 3 (revision 13-jul-2026): agrega 3 campos de captura clinica que
-- existen en la Hoja de Valoracion de Ingreso pero no en el esquema:
--   1. WIfI (Wound/Ischemia/foot Infection) junto a Wagner, pie diabetico.
--   2. Braden (score de riesgo de LPP, 6-23), obligatorio si etiologia = LPP.
--   3. HbA1c (hemoglobina glucosilada), distinta de la glucosa capilar
--      (wound_assessments.glucose_mg_dl, que ya existia).
-- Ninguno de estos entra todavia al motor "Protocolo Kura+"; son de captura
-- clinica unicamente (ver seccion 8 de docs/kura_protocol_engine.md). Si en
-- el futuro alguno alimenta el motor, se debe versionar el motor aparte.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. WIfI (Society for Vascular Surgery): 3 subescalas independientes 0-3,
--    graduadas junto a wagner_grade en la tabla wounds (mismo patron de
--    "campos condicionales por etiologia" ya usado para wagner/ceap/wuwhs).
-- ---------------------------------------------------------------------------
alter table public.wounds
  add column if not exists wifi_wound smallint check (wifi_wound between 0 and 3),
  add column if not exists wifi_ischemia smallint check (wifi_ischemia between 0 and 3),
  add column if not exists wifi_infection smallint check (wifi_infection between 0 and 3);

comment on column public.wounds.wifi_wound is 'WIfI - grado de Herida (Wound), 0-3. Pie diabetico, junto a Wagner.';
comment on column public.wounds.wifi_ischemia is 'WIfI - grado de Isquemia (Ischemia), 0-3. Pie diabetico, junto a Wagner.';
comment on column public.wounds.wifi_infection is 'WIfI - grado de Infeccion del pie (foot Infection), 0-3. Pie diabetico, junto a Wagner.';

-- ---------------------------------------------------------------------------
-- 2. Braden (escala de riesgo de LPP): score total 6-23 (a menor score,
--    mayor riesgo). Se captura por consulta, igual que el resto de
--    wound_assessments. Obligatorio en la UI cuando wounds.etiology = 'lpp'
--    (la constraint de BD queda como rango valido, no como "requerido si
--    LPP" para no acoplar wound_assessments a wounds.etiology).
-- ---------------------------------------------------------------------------
alter table public.wound_assessments
  add column if not exists braden_score smallint check (braden_score between 6 and 23);

comment on column public.wound_assessments.braden_score is 'Escala de Braden (riesgo de LPP), score total 6-23. Obligatorio en UI cuando la etiologia de la herida es LPP.';

-- ---------------------------------------------------------------------------
-- 3. HbA1c (hemoglobina glucosilada, %): distinta de glucose_mg_dl (glucosa
--    capilar puntual, ya existente). Se captura por consulta, condicionada
--    en UI a paciente diabetico / etiologia pie diabetico.
-- ---------------------------------------------------------------------------
alter table public.wound_assessments
  add column if not exists hba1c_pct numeric check (hba1c_pct between 0 and 20);

comment on column public.wound_assessments.hba1c_pct is 'Hemoglobina glucosilada (HbA1c, %). Distinta de glucose_mg_dl (glucosa capilar puntual). Se muestra en UI si el paciente es diabetico o la etiologia es pie diabetico.';
