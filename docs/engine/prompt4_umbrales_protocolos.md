# Prompt 4 — Ajustes al motor de reglas: umbrales por protocolo

Documentación de qué umbral viene de qué protocolo, para validación clínica
(Dra. Capistrán / María). Todo el cambio vive en `lib/engine/` con tests.

## (a) Interconsultas ampliadas — Protocolo "Interconsultas"

| Regla | Umbral / disparador | Origen | Nota |
|---|---|---|---|
| Geriatría | úlcera vascular (MMII), paciente frágil, **LPP recurrente**, **cuidados paliativos**, **dolor crónico** | Protocolo "Interconsultas" | Se emite UNA interconsulta con todos los motivos aplicables. |
| Angiología por ITB | **ITB < 0.9 o > 1.4** | Protocolo "Interconsultas" (+ "Úlceras MMII") | Aplica a **cualquier etiología** con extremidad inferior evaluada. |

**Coordinación con el fix arterial (Prompt 1):** la derivación a angiología por
ITB se **centralizó** en las interconsultas generales (paso 9 del motor) y se
**eliminó** la versión duplicada que vivía dentro de `_applyVascularRules`. El
paso 9 hace *dedup*: si la isquemia crítica (paso 2) o la rama de terapia seca
(Prompt 1) ya agregaron una interconsulta a angiología, no se duplica. Resultado:
**exactamente una** interconsulta a angiología por caso.

## (b) Umbrales de Sheehan por etiología — Protocolos "etiologías" / Sheehan

Hito de cicatrización esperada (semana de control / % de reducción de área):

| Etiología | Hito | Origen |
|---|---|---|
| Pie diabético (UPD) | **8 semanas / 50%** | Protocolo etiologías/Sheehan |
| Vascular (MMII) | **4 semanas / 40%** | Protocolo etiologías/Sheehan |
| LPP | **8 semanas / 50%** | Protocolo etiologías/Sheehan |
| Quirúrgica | **4 semanas / 50%** | Protocolo etiologías/Sheehan |
| Traumática / otra | (sin hito propio) | usan la tabla genérica por semana 8.5 |

**Modelado (a confirmar por María):** el % de cierre esperado escala
linealmente de 0 (semana 0) al % del hito en su semana de control, y se mantiene
plano después. El umbral de **alerta = 0.6 × umbral de cierre** (consistente con
la tabla genérica en semana 4: 30/50). `evaluate(..., etiologia: ...)` usa estos
hitos; sin `etiologia` conserva la tabla genérica histórica (compatibilidad).

## (c) Braden → modalidad de tratamiento en LPP — Protocolo LPP

| Rango de Braden | Modalidad sugerida | Origen |
|---|---|---|
| **≤ 12** (riesgo alto/muy alto) | A cargo de la clínica | bandas estándar de Braden + intención del protocolo LPP |
| **≥ 13** (moderado/bajo/sin riesgo) | Tratamiento compartido (clínica + cuidador) | ídem |

**A confirmar por María:** las bandas de Braden son las estándar; el punto de
corte 12/13 para separar "a cargo de clínica" vs "compartido" es una decisión de
modelado del motor, pendiente de validación clínica. Solo aplica a etiología LPP.

## (d) Referencia por túnel > 7 cm o articulación — Protocolo "Interconsultas"

| Disparador | Referencia | Origen |
|---|---|---|
| **Túnel > 7 cm** | Cirugía (descartar trayecto fistuloso/absceso) | Protocolo "Interconsultas" |
| **Compromiso articular** | Cirugía / Ortopedia (descartar artritis séptica / exposición articular) | Protocolo "Interconsultas" |

## Campos de entrada nuevos (`KuraEngineInput`)

`bradenScore`, `lppRecurrente`, `cuidadosPaliativos`, `dolorCronico`,
`tunnelDepthCm`, `sobreArticulacion`. `bradenScore` ya se captura en el
formulario de LPP y se conecta al motor; los demás quedan **pendientes de
captura en el formulario** (por defecto no disparan nada).

## Tests

`test/engine/kura_treatment_rules_engine_test.dart` (geriatría, angiología sin
duplicar, Braden, túnel/articulación) y
`test/engine/kura_sheehan_checkpoint_test.dart` (hitos por etiología). Suite del
motor: 102/102 verde; `flutter analyze` sin errores.
