-- =============================================================================
-- 0077_protocol_rule_conditions.sql — Reglas de producto MULTI-CONDICIÓN
-- =============================================================================
-- El apósito (y otros pasos) depende de varios factores que el motor ya conoce:
-- exudado, zona anatómica, tamaño (área — 0076) y riesgo de infección. Aquí las
-- reglas de protocolo ganan CONDICIONES opcionales; una regla aplica si se
-- cumplen TODAS sus condiciones, y entre las que aplican gana la MÁS ESPECÍFICA
-- (más condiciones). Reglas sin condiciones = comodín general (comportamiento
-- 0076 intacto).
--
--   exudate_levels jsonb  — niveles de exudado que matchea (ExudadoCantidad:
--                           ninguno/escaso/moderado/abundante). [] = cualquiera.
--   zone_groups    jsonb  — grupos de zona (sacro_gluteo/talon_pie/pierna_mmii/
--                           tronco/otro). [] = cualquiera.
--   infection      text   — 'any' | 'yes' | 'no' (riesgo/sospecha de infección).
--   priority       int    — desempate cuando hay misma especificidad.
--
-- Aditivo: solo agrega columnas nullable con default; no toca RLS.
-- =============================================================================

alter table public.protocol_product_rules
  add column if not exists exudate_levels jsonb not null default '[]'::jsonb,
  add column if not exists zone_groups jsonb not null default '[]'::jsonb,
  add column if not exists infection text not null default 'any',
  add column if not exists priority int not null default 0;

comment on column public.protocol_product_rules.exudate_levels is
  'Niveles de exudado (ExudadoCantidad) que matchea la regla; [] = cualquiera.';
comment on column public.protocol_product_rules.zone_groups is
  'Grupos de zona anatómica que matchea; [] = cualquiera.';
comment on column public.protocol_product_rules.infection is
  'Condición de infección: any | yes | no (riesgo/sospecha local).';
