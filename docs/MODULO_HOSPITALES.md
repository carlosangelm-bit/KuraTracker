# Módulo de Hospitales (Prevención hospitalaria) — referencia técnica

Documento **as-built**: describe el módulo de hospitales de KuraTracker **tal como está
implementado hoy** en el código. Para el plan/spec por fases de las **escalas** de
valoración cutánea, ver [`modulo_hospitalizacion.md`](modulo_hospitalizacion.md).

> **Naturaleza del módulo:** es una **capa documental / de apoyo a la decisión**. No
> modifica el motor de tratamiento de heridas ni auto-prescribe. La cabecera de la
> migración base (`0036`) y el disclaimer en la app lo dejan explícito: *"Apoyo a la
> decisión (borrador clínico). No sustituye el juicio profesional ni modifica el plan de
> tratamiento."*

> ⚠️ **Estado clínico:** reglas, cadencias, umbrales de escalas, paletas de color y textos
> de instrucciones siguen siendo **BORRADOR pendiente de validación de María**. Ver
> [§9 Pendientes](#9-pendientes--borradores).

---

## 1. Qué es y para qué sirve

Un **centro de tipo hospital** activa un flujo centrado en la **prevención de lesiones**
(principalmente LPP) y el **cuidado por rondas**, en lugar del flujo de consulta/tratamiento
de la clínica de heridas. El ciclo de trabajo:

```
Enfermería valora (triage + escalas)  →  se determina el nivel de riesgo (banda Braden)
   →  el especialista (clínico) define el plan de cuidados
   →  enfermería ejecuta las tareas en las rondas  →  se mide el cumplimiento
```

Tres diferencias clave frente a la clínica de heridas:

1. **Acceso center-wide**: cualquier staff activo del centro ve a **todos** los pacientes
   del hospital (no hace falta asignación 1:1).
2. **Tareas sin dueño**: las tareas preventivas **siguen al paciente**, no a un profesional;
   quien las ejecuta queda registrado en `done_by`.
3. **Agenda = Rondas**: la pestaña de agenda enruta a la **agenda de prevención**
   (`/prevention-agenda`), no a la agenda de citas.

---

## 2. Tipo de centro "hospital"

- **Modelo**: `lib/models/center_type.dart` — `enum CenterType { clinicaHeridas, hospital,
  cuidadores }`; valor en BD `'hospital'` (columna `organizations.center_type`).
- **Organización**: `lib/models/organization.dart` — `centerType`, y `enabledScales`
  (columna `enabled_scales`, ver §6).
- **Paleta azul**: `lib/core/design/tokens.dart` → `BrandTokens.hospital`
  (`brandPrimary 0xFF2563EB`, fondo frío `0xFFF3F6FC`). Se aplica en toda la app vía
  `BrandTokens.of(context)` según el centro activo. Los colores de semáforo/estado son
  **compartidos** entre tipos de centro (son clínicos, no decorativos).
  ⚠️ El azul (y el rosa de cuidadores) están marcados como **BORRADOR de color** en el
  código.
- **Módulos por defecto**: `lib/models/module_key.dart` `defaultFor` — hospital habilita
  todos los módulos (incluida Prevención); clínica de heridas trae Prevención **apagada**
  por defecto; eKare **no** está disponible en hospital.
- **Detección en runtime**: `repo.centerTypeFor(orgId) == CenterType.hospital` o
  `session.activeCenterType == CenterType.hospital`.

---

## 3. Roles: clínico vs enfermería

`lib/models/app_user.dart` — `enum AppRole { admin, clinico, master, cuidador, enfermeria }`.
Regla central: **`canDiagnose => role == clinico || role == admin`** (enfermería queda
fuera).

| Capacidad | Clínico / Admin | Enfermería |
|---|---|---|
| Ver a todos los pacientes del centro | ✅ | ✅ |
| Correr triage y escalas | ✅ | ✅ |
| **Definir** el plan de cuidados | ✅ ("Definir plan de cuidados") | ❌ (solo "Ver plan / rondas") |
| Ejecutar tareas en rondas (marcar hecha/saltar) | ✅ | ✅ |
| Registrar valoraciones (Braden/escalas), ingresos, eventos adversos | ✅ | ✅ |
| Escritura de diagnóstico/protocolo center-wide | ✅ (solo clínico) | ❌ |

**En BD (RLS, migración `0045`):**
- `has_hospital_org_access(patient)` = el paciente pertenece a un centro `center_type =
  'hospital'` **y** el usuario es un staff **activo** de ese centro → base del acceso
  center-wide (SELECT para todos; sin necesidad de `staff_patient_assignments`).
- **Grupo A** (write diagnóstico/protocolo): **solo clínico**.
- **Grupo B** (report/ejecución: `risk_assessments`, `patient_admissions`,
  `adverse_events`, `preventive_tasks`, `preventive_action_log`): **clínico y enfermería**.
- A enfermería se le **niega** deliberadamente el `staff_patient_assignments`, para que no
  herede el write de clínico.

---

## 4. Rutas y navegación

Rutas (dentro del `ShellRoute`, `lib/core/router/app_router.dart`):

| Ruta | Pantalla | Notas |
|---|---|---|
| `/risk` | `RiskBoardScreen` | Panel/tablero de prevención (nav: "Prevención") |
| `/prevention-agenda` | `PreventionAgendaScreen` | Agenda de prevención / rondas |
| `/hospital` | `HospitalDashboardScreen` | Dashboard del centro (solo hospital) |
| `/patients/:id/risk` | `PatientRiskScreen` | Perfil de prevención y riesgo del paciente |

**Gating**: `/prevention-agenda` y `/hospital` son submódulos de `ModuleKey.prevention`; si
el módulo está apagado en el centro, redirigen a `/`.

**Navegación** (`lib/core/router/app_shell.dart`, `_itemsFor`):
- En hospital, la pestaña de agenda pasa a llamarse **"Rondas"** → `/prevention-agenda`
  (icono `checklist`). En otros centros es "Agenda" → `/agenda`.
- `/risk` aparece como **"Prevención"** (icono `shield`) siempre que el módulo esté
  habilitado.
- **`/hospital` no tiene ítem de navegación**: se llega desde el botón de insights del
  tablero de riesgo.

**Bloqueo de enfermería**: el redirect de escritura para `enfermeria` bloquea alta/edición
de paciente, consultas, captura de herida, plan, seguimiento, comorbilidades, diagnósticos
y referencias — pero **no** bloquea `/risk`, `/prevention-agenda`, `/hospital` ni
`/patients/:id/risk`.

---

## 5. Pantallas

### 5.1 Tablero de prevención — `lib/features/risk/risk_board_screen.dart`
- Título "Prevención". Botón **"Dashboard del centro"** (→ `/hospital`) visible solo si el
  centro es hospital; botón de agenda (→ `/prevention-agenda`).
- Muestra pacientes con alertas o con **ingreso activo**. El clínico ve solo sus pacientes
  asignados; admin/enfermería ven a todos los del centro.
- Por paciente: riesgo calculado, ingreso activo, **último Braden**, **% de cumplimiento**,
  **flag de vencidas**.
- **Banda por Braden** (`bradenBandLevel`, función canónica reusada por dashboard y agenda):
  **≤12 alto (rojo) · 13–17 medio (ámbar) · 18–23 bajo (verde) · sin valoración = gris**.
- Orden por nivel (alto arriba; sin-valoración al final). Filtros: nivel, **piso**, **área**.
  Escritorio (≥900px) = tarjetas; móvil = lista. Tocar un paciente → perfil de riesgo.

### 5.2 Agenda de prevención / Rondas — `lib/features/prevention_agenda/prevention_agenda_screen.dart`
- Renderiza `PreventiveTasksView`: toggle **día/semana**, navegación de fecha, filtros por
  **paciente / piso / área / banda de riesgo** (cola de rondas del turno), barra de
  adherencia.
- Tareas pendientes agrupadas por día; completadas colapsadas al final.
- `_TaskTile`: hora, título, enlace al paciente, **ubicación** (`activeAdmission.
  locationLabel`), flag de vencida, y acciones **"marcar hecha" / "saltar"** que registran
  `done_by`/`staffId`.
- Cada actividad tiene icono/color por `actionId` e **instrucciones orientativas** ("cómo
  se realiza") en un diálogo — texto **sujeto a validación clínica**.

### 5.3 Perfil de prevención y riesgo — `lib/features/risk/patient_risk_screen.dart`
- Título "Prevención y riesgo". Banner de nivel de riesgo, botón de plan de cuidados,
  tarjeta de escalas a realizar, tiles informativos.
- **Braden** (`_assessBraden`): guarda `risk_assessments`; en hospital dispara
  `autoGeneratePlanIfHospital` para materializar el plan esperado.
- **Plan de cuidados**: si `canDiagnose` → "Definir plan de cuidados" (abre el constructor);
  si no → "Ver plan de cuidados (rondas)" (→ `/prevention-agenda`).
- **Ingreso/egreso** (`_admit`/`_discharge`): captura **piso / área / cama**.
- **Escalas** (`_assessScale`): despacha PUSH, RESVECH, ASEPSIS (suma), Quemadura (Garcés),
  GLOBIAD, ISTAP, STAR, MARSI, Extravasación, NPIAP, Wagner, CEAP, MDRPI (categóricas).
  `_doTriage` captura los factores que determinan qué escalas aplican.
- Panel de **cumplimiento** y **bitácora de auditoría** (cronología de valoraciones y
  actividades). Disclaimer de apoyo a la decisión al pie.

### 5.4 Dashboard del centro — `lib/features/hospital_dashboard/hospital_dashboard_screen.dart`
- **Solo hospital** (guarda con `centerTypeFor != hospital`). Población = pacientes con
  ingreso activo.
- KPIs: encamados, alto riesgo, sin valoración, vencidas, % de cumplimiento.
- Tarjetas: distribución de riesgo; cumplimiento por **tipo / piso / área / turno** (hoy);
  alto riesgo **sin revisión**; **tendencia** de 7 días; **actividad de enfermería** (7
  días por `done_by`); **editor de turnos** (solo admin/master); y el **placeholder de
  incidencia/prevalencia de LPP**.
- Solo lectura, excepto el editor de turnos (`setShiftConfig`).

### 5.5 Triage + hojas de escala — `lib/features/risk/`
`triage_sheet.dart` (cuestionario de factores → aplicabilidad), `braden_scale_sheet.dart`,
`sum_scale_sheet.dart` (PUSH/RESVECH/ASEPSIS), `category_sheet.dart` (categóricas:
NPIAP/Wagner/CEAP/MDRPI), `globiad_sheet.dart`, `istap_sheet.dart`, `star_sheet.dart`,
`marsi_sheet.dart`, `extravasacion_sheet.dart`, `quemaduras_sheet.dart`.

### 5.6 Constructor del plan de cuidados — `lib/features/prevention/caregiver_plan_builder_sheet.dart`
- Pre-marca las acciones aplicables (`schedulableActionsFor(computeRisk(...))`), lista las
  cadencias del catálogo, permite indicaciones libres y "omitir cuidados nocturnos".
- Al confirmar: en **hospital** las tareas van **sin dueño** (`assignee=null`, kind
  `'staff'`); en cuidadores/clínica se asignan al cuidador del paciente si existe. Llama a
  `generatePreventiveTasksFromSpecs`.

---

## 6. Modelo de datos y migraciones

| Migración | Aporta |
|---|---|
| `0036_prevention_module.sql` | `patient_admissions` (unit, bed, admitted/discharged, status), `risk_assessments` (braden_score 6–23, subscores, assessed_by/at). RLS clínica + auditoría. |
| `0042_preventive_tasks.sql` | `caregiver_patient_assignments` + `is_caregiver_of()`; **`preventive_tasks`** (patient, admission, rule_id, action_id, title, scheduled_at, assignee_profile_id, assignee_kind, recurrence, status pending/done/skipped/canceled, done_at/by, source auto/manual). |
| `0045_nurse_role_hospital_access.sql` | enum `'enfermeria'`; `is_nurse()`, **`has_hospital_org_access()`**; políticas aditivas `*_hospital_select` (todo el staff activo) y `*_hospital_write` (Grupo A clínico, Grupo B clínico+enfermería). |
| `0046_hospital_prevention.sql` | `patient_admissions.floor` y `.area`; `organizations.shift_config` jsonb; RPC `set_shift_config`. |
| `0084_scale_assessments.sql` | **`scale_assessments`** genérica (scale_id, subscores, total_score, category_result, band_id) — resultado de cualquier escala puntuable/categórica. |
| `0085_enabled_scales.sql` | `organizations.enabled_scales` (jsonb array; NULL = todas) + RPC `set_enabled_scales`. |

Tablas/funciones adyacentes que el código usa: `preventive_action_log` (`0037`, append-only),
`caregiver_generate_tasks` (`0043`), `caregiver_instructions` (`0044`).

**Acceso center-wide (resumen RLS):** `has_hospital_org_access(patient)` habilita SELECT a
todo staff activo del hospital; el write se separa en Grupo A (diagnóstico/protocolo, solo
clínico) y Grupo B (report/ejecución, clínico+enfermería). `preventive_action_log` es
**append-only** (solo INSERT).

---

## 7. Motor de reglas y generación del plan de cuidados

**Braden** (`assets/engine/braden_scale.json`): 6 ítems, total 6–23; niveles muy_alto 6–9,
alto 10–12, medio 13–17, bajo 18–23. La app colapsa muy_alto+alto en **alto (≤12)**.

**Motor** (`lib/engine/risk/prevention_risk_engine.dart` + `assets/engine/prevention_rules.json`):
- `computeRisk` (`data_repository.dart`) alimenta al motor con **comorbilidades presentes +
  heridas activas + último Braden**. `evaluate(...)` casa reglas declarativas cuya gramática
  `when` soporta: `bradenMin/Max`, `comorbilidad`, `hasActiveWound`, `mobilityIn`, `fragile`,
  `bmiMax`, `woundEtiology`, `deterioration`.
- `schedulableActionsFor` solo agenda las acciones que tienen **cadencia** definida.
- El catálogo tiene **8 acciones con cadencia**: `cambios_2h_registro` (2h),
  `cambios_2_3h` (3h), `cambios_4h` (4h), `agho` (12h), `control_humedad` (8h),
  `exam_piel_diario` (24h), `valoracion_piel_completa_diaria` (24h), `aposito_preventivo`
  (24h).

**Flujo de generación:**
1. Se guarda Braden → (hospital) `autoGeneratePlanIfHospital` → `generatePreventiveTasksFor`
   → `computeRisk` → `schedulableActionsFor` → `generatePreventiveTasksFromSpecs`.
2. `generatePreventiveTasksFromSpecs` es **idempotente**: borra las tareas AUTO futuras
   pendientes y re-materializa cada spec `floor(horizonte/cada_horas)` veces (tope 1–24),
   saltando 22:00–06:00 si `skipNight`. **No toca** tareas manuales/hechas/saltadas.
3. Override manual: el constructor del plan (clínico/admin) re-selecciona acciones
   (`rule_id = 'profesional'`) y añade indicaciones libres, usando el mismo materializador.

> **⚠️ Limitación actual (importante):** el plan de cuidados se calcula **solo a partir de
> Braden** (+ comorbilidades + etiología) y **solo emite las 8 acciones genéricas con
> cadencia**. Los resultados de las demás escalas (ISTAP, STAR, GLOBIAD, MARSI, quemaduras,
> SUM…) **no entran** a `computeRisk`, no hay reglas que los mapeen a acciones, y aunque
> Braden tiene acciones más ricas (colchón antiescaras, MNA, ajuste proteico, SEMP), estas
> **no tienen cadencia** y por eso nunca se agendan. Por eso en el triage "solo se muestran
> acciones genéricas". Cerrar esto requiere: (a) que `computeRisk` lea cada escala, (b)
> reglas por escala/banda, y (c) cadencias para esas acciones — **contenido clínico
> pendiente de validación de María**.

---

## 8. Turnos y cumplimiento

- **`organizations.shift_config`** (`0046`): lista `[{name, startHour, endHour}]`; NULL =
  ventana de **24 h**; `endHour < startHour` cruza medianoche. Se edita en el dashboard
  (`setShiftConfig` / RPC `set_shift_config`, master/admin).
- **`complianceWindowStart(orgId, now)`**: inicio del turno actual (maneja el cruce de
  medianoche) o `now − 24h` si no hay turnos configurados.
- **`preventiveCompliance(patientId, orgId, now)`**: cuenta tareas programadas en
  `[windowStart, now]` (no canceladas); agrega **hechas/esperadas** global y **por tipo**.
  Es la **fuente única** usada por el tile del paciente, el tablero y el dashboard.
- **Vencidas**: `tarea.pendiente && scheduled_at < now`.
- **Colores de cumplimiento**: ≥85% verde, ≥60% ámbar, si no rojo.

---

## 9. Pendientes / borradores

Todo lo siguiente está marcado en el código como borrador/pendiente:

- **Reglas y cadencias de prevención** (`prevention_rules.json`, motor): BORRADOR pendiente
  de validación de María. Incluye la limitación de §7 (acciones derivadas de escalas).
- **Incidencia/prevalencia de LPP**: placeholder en el dashboard — pendiente de definición
  clínica (numerador / denominador / ventana).
- **Paletas azul (hospital) y rosa (cuidadores)**: colores BORRADOR, ajustables tras validar
  la Fase 1.
- **Instrucciones de actividades en rondas**: texto orientativo sujeto a validación clínica.
- **Sub-puntajes / umbrales de escalas** (RESVECH/PUSH/ASEPSIS, Garcés/ABA, pesos de
  aplicabilidad): BORRADOR.
- **Escalas no implementadas**: se muestran como "Próximamente".
- **Señal de deterioro** (`deterioration`): hook de fase 2 sin conectar; la regla
  `complic_deterioro` aún no dispara.

---

## Ver también
- [`modulo_hospitalizacion.md`](modulo_hospitalizacion.md) — plan/spec por fases del
  submódulo de **escalas** de valoración cutánea.
- [`MANUAL.md`](MANUAL.md) — manual clínico/funcional completo.
