-- =============================================================================
-- 0107_module_settings_key_chk_all_modules.sql
-- =============================================================================
-- El CHECK original de module_settings (0041) solo admitía 5 de los módulos:
--   check (module_key in ('patients','agenda','prevention','reports','ekare'))
-- Después se agregaron al enum de la app (lib/models/module_key.dart) tres
-- módulos más —'insumos', 'comercial' y 'vac'— pero ninguna migración amplió
-- el CHECK. Consecuencia en PRODUCCIÓN: el master que intenta apagar Insumos,
-- Comercial o Terapia VAC en un centro recibe una violación de constraint
-- (23514). En la demo no se nota: LocalStore no tiene constraints.
--
-- Este arreglo reemplaza el CHECK por la lista COMPLETA de los ocho módulos.
-- Es aditivo (solo amplía lo permitido; no invalida ninguna fila existente) y
-- de bajo riesgo. El valor 'ekare' se conserva tal cual: el módulo se relabeló
-- a "Importar expedientes" en la UI, pero su clave persistida no cambia.
-- =============================================================================

alter table public.module_settings
  drop constraint if exists module_settings_key_chk;

alter table public.module_settings
  add constraint module_settings_key_chk
  check (module_key in (
    'patients', 'agenda', 'prevention', 'reports',
    'ekare', 'insumos', 'comercial', 'vac'
  ));
