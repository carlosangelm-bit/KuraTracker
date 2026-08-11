# Módulo de Hospitalización — plan y arquitectura

Spec viva del módulo de valoración/clasificación/seguimiento de lesiones cutáneas
hospitalarias. Complementa (no reemplaza) el manual clínico completo entregado por el
equipo; aquí se registra **cómo se implementa en KuraTracker**.

## Principio rector (acordado con el equipo)

Lo importante **no** es la escala en sí, sino el **motor de decisión**:

1. **Aplicabilidad (routing):** según las **características del paciente** (comorbilidades,
   incontinencia/humedad, dispositivos, adhesivos, herida quirúrgica, diabetes, insuf.
   venosa, quemadura, extravasación…), saber **qué escalas son aplicables/sugeridas**.
2. **Riesgo → tratamiento:** según el **nivel de riesgo** (y el resultado de la escala),
   **qué tratamiento preventivo se registra en la bitácora** (tareas de `preventive_tasks`
   + `preventive_action_log`).

La escala es solo un **input**. Cada escala debe poder **realizarse en la plataforma**
(guiada, ítem por ítem, con el resultado calculado) **y** permitir **capturar el score
manualmente** si el usuario ya lo tiene (igual que Braden).

El **flujo se conserva**: enfermería valora (cuestionario/escala) → se determinan escalas
y nivel → el especialista define el plan de cuidados → enfermería ejecuta en las rondas.

## Arquitectura (reutiliza lo que ya existe)

- **Definiciones declarativas** como el asset de Braden (`assets/engine/braden_scale.json`
  + loader cacheado) y la disciplina de procedencia/validación de `ClinicalParams`
  (parametrizable y auditable, editable sin recompilar).
- **Tabla genérica `scale_assessments`** (migración `0084`) para el resultado de cualquier
  escala puntuable/repetible: `scale_id`, `subscores` jsonb, `total_score`,
  `category_result` (p. ej. GLOBIAD `2A`), `band_id`, `assessed_by/at`. Append-only, mismo
  patrón que `risk_assessments` (Braden). RLS clínica + acceso hospitalario center-wide
  (`has_hospital_org_access`, 0045).
- Las **clasificaciones por etiología** (Wagner/CEAP/NPUAP/Texas/Rutherford/WUWHS/WIfI/IDSA)
  siguen como **columnas de `wounds`** (ya existen); el motor nuevo es para escalas
  **repetibles/puntuables**, no para reescribir esas.
- **Routing y riesgo→tratamiento** viven en el motor de prevención existente:
  `PreventionRulesCatalog` (reglas declarativas en `assets/engine/prevention_rules.json`) y
  `buildPreventivePlan`. Las escalas nuevas se enchufan como (a) reglas de aplicabilidad y
  (b) mapeos de resultado → acciones/cadencias en la bitácora.

## Inventario de escalas (existe vs nuevo)

| Escala | Estado | Dónde |
|---|---|---|
| Braden | ✅ existe (data-driven) | `braden_scale.json`, `risk_assessments` |
| NPIAP/NPUAP/EPUAP | ✅ existe | `NpuapEstadio`, `wounds.npuap_estadio` |
| Wagner | ✅ existe | `WagnerGrade`, `wounds.wagner_grade` |
| CEAP | ✅ existe | `CeapClass`, `wounds.ceap_class` |
| **GLOBIAD** | ✅ hecho (Fase 0) | `globiad_sheet.dart`, `scale_assessments` |
| PUSH | ⬜ nuevo | — |
| RESVECH 2.0 | ⬜ nuevo | — |
| ISTAP | ⬜ nuevo | — |
| STAR | ⬜ nuevo | — |
| MDRPI (+Glamorgan) | ⬜ nuevo | — |
| MARSI | ⬜ nuevo | — |
| Extravasación | ⬜ nuevo | — |
| ASEPSIS / dehiscencia | ⬜ nuevo | — |
| Quemaduras / Garcés | ⬜ nuevo | — |

## Plan por fases

- **Fase 0 — Infraestructura** ✅: tabla `scale_assessments` + modelo + repo + patrón de
  captura guiada/manual. **Hecho.**
- **Fase 1 — Núcleo LCRD nuevo**: GLOBIAD ✅, ISTAP, STAR, PUSH, RESVECH 2.0 + su routing
  (incontinencia→GLOBIAD, fricción→ISTAP/STAR, lesión activa→PUSH/RESVECH).
- **Fase 2 — Clasificación + ciclo de vida** de la lesión + alertas de deterioro.
- **Fase 3 — Alto impacto**: Extravasación (monitoreo c/4h), ASEPSIS/DHQ.
- **Fase 4 — Resto**: MDRPI (+Glamorgan pediatría), MARSI, Quemaduras/Garcés (+criterios
  ABA). Requiere ampliar el enum de etiologías.
- **Fase 5 — Analítica**: tendencias por lesión + indicadores de calidad (incidencia
  intrahospitalaria por etiología/unidad).
- **Transversal**: scheduler de reevaluación por turno + conexión de alertas/escalamiento.

## Ejemplo implementado: GLOBIAD (Fase 0)

- **Aplicabilidad:** en el perfil de riesgo aparece cuando la subescala **humedad de
  Braden ≤ 2** (piel húmeda/muy húmeda) y **Braden ≤ 17** (riesgo ≥ medio), o si ya hay
  valoración previa.
- **Captura** (`globiad_sheet.dart`): **Realizar** (CAT1/CAT2 + ¿infección? → 1A/1B/2A/2B)
  o **capturar** el resultado manualmente.
- **Riesgo → tratamiento:** en centros hospital, **2A/2B** agenda `control_humedad`
  (barrera cutánea) en la bitácora; subcategoría **B** (infección) añade vigilancia.
  Idempotente por `rule_id = 'globiad'` (no toca el plan de Braden).

## Convenciones (del manual clínico)

- Toda valoración es **inmutable y trazable** (timestamp, responsable); las correcciones
  son nuevas valoraciones.
- **NULL** (no capturado) ≠ **N/A** (no aplica).
- Los sub-puntajes de escalas parametrizables (RESVECH, PUSH-área, ASEPSIS, Glamorgan) se
  cargan como **tablas de configuración** validadas por el equipo clínico, no hardcodeadas.
- Sugerencias terapéuticas (p. ej. compresión CEAP) se muestran como **recomendación con
  advertencias**, nunca auto-prescripción. Apoyo a la decisión, no sustituye juicio clínico.
