# Libro de Parámetros Clínicos

> **Generado automáticamente** desde `assets/engine/clinical/thresholds.json` y `archetypes.json` por `test/engine/parametros_libro_generator_test.dart`. No editar a mano: cambiar un valor se hace en el JSON (con su procedencia) y este libro se regenera al correr los tests.

Versión de parámetros: `clinical_params_v1`.

## Umbrales

| Parámetro | Valor | Unidad | Protocolo | Justificación | Revisado por | Fecha |
|---|---|---|---|---|---|---|
| `debridement_composition_min_pct` | 15 | % | Protocolo de desbridamiento | Esfacelo + necrosis >= 15% del lecho justifica desbridamiento cuando NO hay isquemia crítica ni terapia seca. | María | 2026-07-20 |
| `necrosis_extensa_min_pct` | 30 | % | Protocolo de interconsultas | Necrosis >= 30% se considera extensa y motiva valoración por cirugía. | María | 2026-07-20 |
| `depth_relleno_min_cm` | 0.5 | cm | Protocolo de curación húmeda | Profundidad >= 0.5 cm (o tunelización/socavamiento) requiere relleno de cavidad. | María | 2026-07-20 |
| `infeccion_local_min_factores` | 2 | factores | Criterios IWII (kura_rules_v2) | >= 2 factores locales significativos = sospecha de infección local (antimicrobiano tópico). | María | 2026-07-20 |
| `tunel_referencia_min_cm` | 7.0 | cm | Protocolo de interconsultas | Túnel > 7 cm exige estudios de imagen y valorar interconsulta (trayecto fistuloso/absceso). | María | 2026-07-20 |
| `braden_a_cargo_clinica_max` | 17 | puntos Braden | Protocolo LPP | Braden <= 17 (riesgo medio/alto/muy alto) => tratamiento a cargo de la clínica; 18-23 (bajo) => compartido. Bandas validadas por María (2026-07). | María | 2026-07-20 |
| `braden_alto_muy_alto_max` | 12 | puntos Braden | Protocolo LPP | Braden <= 12 = riesgo alto/muy alto; 13-23 = riesgo moderado/bajo. Solo etiqueta descriptiva de la justificación (la conducta la fija braden_a_cargo_clinica_max). | María | 2026-07-20 |
| `abi_incompresible_above` | 1.4 | ITB | Protocolo Úlceras MMII | ITB > 1.4 = arterias incompresibles / calcificación (NO buena perfusión). | María | 2026-07-20 |
| `abi_high_min` | 0.8 | ITB | Protocolo Úlceras MMII | ITB >= 0.80 (y <= 1.4) = perfusión adecuada (categoría alta para el pronóstico). | María | 2026-07-20 |
| `abi_mod_min` | 0.5 | ITB | Protocolo Úlceras MMII | ITB >= 0.50 y < 0.80 = perfusión moderada; ITB < 0.50 = isquemia crítica (NO desbridar). | María | 2026-07-20 |
| `albumina_normal_min` | 3.5 | g/dL | Valoración nutricional | Albúmina >= 3.5 g/dL = normal. | María | 2026-07-20 |
| `albumina_mild_min` | 3.0 | g/dL | Valoración nutricional | Albúmina 3.0-3.49 g/dL = déficit leve; < 3.0 = déficit. | María | 2026-07-20 |

## Bandas de compresión

Dominio: **ITB**. Calibración de la terapia compresiva por ITB. Bandas contiguas, sin huecos ni traslapes, cubren todo el rango de ITB medido. _(Protocolo: Protocolo Úlceras MMII; revisado por María, 2026-07-20)_.

| Banda | Rango (ITB) |
|---|---|
| `noAplica` | (−∞, 0.6) |
| `reducida` | [0.6, 0.8) |
| `precaucion` | [0.8, 0.9) |
| `fuerte` | [0.9, 1.4] |
| `incompresible` | (1.4, +∞) |

## Mapeos por grado

### `wagner_descarga`

Dispositivo de descarga por grado Wagner (pie diabético). _(Protocolo: Protocolo Pie Diabético; Descarga escalonada según el grado Wagner de la úlcera. Revisado por María, 2026-07-20)_.

| Clave | Valor |
|---|---|
| `g0` | Calzado terapéutico / plantilla de descarga |
| `g1` | Calzado terapéutico / plantilla de descarga |
| `g2` | Bota walker removible (descarga parcial) |
| `g3` | TCC (Total Contact Cast) o bota walker con descarga total |
| `g4` | TCC (Total Contact Cast) o bota walker con descarga total |
| `g5` | Descarga total + valoración quirúrgica urgente |

### `wuwhs_manejo`

Manejo de la herida quirúrgica por grado WUWHS. _(Protocolo: Clasificación WUWHS de herida quirúrgica; Intensidad del manejo local + interconsulta escalonada por grado WUWHS. Revisado por María, 2026-07-20)_.

| Clave | Valor |
|---|---|
| `g1` | Vigilancia + cuidado de herida estándar |
| `g2` | Manejo local intensivo + reevaluación en 48-72h |
| `g3` | Manejo local intensivo + interconsulta a cirugía |
| `g4` | Manejo urgente: dehiscencia/infección grave |

### `compresion_producto`

Producto de terapia compresiva (mmHg) por banda de compresión con perfusión suficiente. _(Protocolo: Protocolo Úlceras MMII; Presión de compresión (mmHg) calibrada a la banda de ITB. Revisado por María, 2026-07-20)_.

| Clave | Valor |
|---|---|
| `fuerte` | Compresión fuerte (30-40 mmHg) |
| `precaucion` | Compresión con precaución (multicomponente reducida) |
| `reducida` | Compresión reducida (máx 20 mmHg) |
| `na` | Compresión moderada (20-30 mmHg) — confirmar ITB antes de iniciar |

