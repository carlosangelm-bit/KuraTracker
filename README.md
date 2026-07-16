# KuraTracker

EHR (expediente clínico electrónico) especializado en **cuidado avanzado de heridas crónicas**, desarrollado para la clínica **Kura+ / CuraMás**. Incluye el motor propietario **Protocolo Kura+**, un servicio de decisión clínica versionado que estima probabilidad de escenario de cierre y sugiere un régimen de tratamiento con reglas de seguridad explícitas.

> ⚠️ **Apoyo a la decisión clínica — no sustituye el juicio clínico.** Esta etiqueta se muestra siempre junto a cualquier sugerencia generada por el motor Kura+.

---

## 1. Estado del proyecto (resumen ejecutivo)

| Área | Estado |
|---|---|
| Motor Protocolo Kura+ (8.1–8.5) | ✅ Completo, 42/42 tests pasando, paridad numérica validada contra referencia Python (tolerancia 1e-8/1e-9) |
| App Flutter (Web/iOS/Android desde una sola base) | ✅ Compila sin errores (`flutter analyze` limpio), build web exitoso |
| Flujo de captura de heridas (rediseñado) | ✅ Completo — inventario clínico original conservado |
| Modelo Centro → Sitios → Personal (multi-tenant) | ✅ Completo en código y migración (`0011_organizations.sql`, ver sección 5.3). **⚠️ Migración 0011 NO aplicada aún** al proyecto Supabase real del cliente — es el único paso manual pendiente antes de que el aislamiento por organización tome efecto en producción |
| Catálogo de notas: alta manual + import/export CSV | ✅ Completo — descarga de plantilla CSV, carga con merge en bloque (agregar/actualizar/omitir) y resumen de importación, además de la alta manual ya existente (ver sección 3.4) |
| Esquema Supabase (SQL: tablas, RLS, triggers, storage) | ✅ Diseñado, versionado en `supabase/migrations/` — **0001→0010 aplicadas y confirmadas en producción**; `0011_organizations.sql` está lista y versionada pero pendiente de aplicar (ver sección 5.3) |
| Persistencia real / multiusuario / RLS en vivo | ✅ Migraciones 0001-0007 aplicadas y **smoke-test end-to-end completado contra Supabase real** (login → paciente → captura → tratamiento con sugerencia Kura+ → seguimiento con checkpoint Sheehan → datos listos para reporte), incl. bug de `search_path` corregido y validado en producción; verificación formal de RLS con prueba negativa (segundo usuario clínico sin asignaciones) sigue diferida hasta antes de cargar datos reales, por decisión del cliente — se avanza con datos sintéticos |
| Registro de seguimiento (visitas subsecuentes) | ✅ **Alineado con protocolos clínicos Kura+ (Prioridad 1) y refinado (UX/fidelidad clínica)** — formulario "Registrar seguimiento" captura reevaluación integral (edema/dolor+EVA/exudado/olor/borde/piel perilesional/infección IWII/adherencia), medición 2D + 3D (volumen en heridas profundas) + nota de medición manual para socavamiento/tunelización. **Las 2 fotografías obligatorias ahora se piden en su momento clínico real** (después de limpiar, ANTES de composición del lecho; con medición, INMEDIATAMENTE DESPUÉS de medir), no al final. La **nota de seguimiento** (tipo de atención/procedimiento/material/evolución) usa chips desde un **catálogo configurable por el admin** (`note_option_catalog`, migración 0010) con opción "Otro" (persistible al catálogo solo por admin). **Firma y cédula profesional se autocompletan de solo lectura** desde el registro `staff` del profesional logueado (aviso si falta cédula, en vez de pedirla en la nota). Persiste todo en Supabase (`visit_type='seguimiento'`). Tablero de seguimiento 100% derivado de la serie real, sin datos de ejemplo, y ahora incluye **alerta de "sin avance en 2–4 semanas → considerar referir a especialista"** (Protocolo de Desbridamiento §13) (ver sección 3.4) |
| Detalle de consulta (solo lectura) desde el historial | ✅ Completo — historial de consultas del paciente es tappable y navega a `ConsultationDetailScreen` (ver sección 3.5) |
| Storage real de fotos (bucket `wound-evidence`) | ✅ Implementado — `PhotoUploadService` sube a Supabase Storage con ruta `{wound_id}/{consultation_id}/...` y resuelve URL firmada; cae a data-URL base64 automáticamente en modo demo sin credenciales |
| Motor como Edge Function (Supabase, TypeScript) | ❌ Pendiente — hoy el motor corre embebido en el cliente Dart |
| Bitácora de auditoría | ⚠️ Parcial — cubre creación de paciente/medición/plan de tratamiento vía trigger SQL; faltan updates/deletes. `wound_assessments`/`wound_photos` no están en la lista de tablas auditadas (por diseño del trigger existente) |
| Import/Export CSV (eKare) | ✅ Demo funcional (mapeo configurable en UI); persistencia real de `import_batches` pendiente |
| Generación de PDF (reportes) | ✅ Funcional en cliente vía `pdf`/`printing` |
| Aislamiento de pacientes por organización (crítico) | ✅ Corregido — antes cualquier admin veía TODOS los pacientes de la base; ahora ve solo los de su organización (ver sección 5.3) |
| Fix admin-clínico (licencia individual) | ✅ Corregido — un admin sin fila `staff` ya puede registrar consultas: `DataRepository.ensureAdminStaffId()` crea la fila de forma perezosa en login/alta de consulta (ver sección 5.3) |
| Fix "pantalla en blanco" al crear concepto de catálogo | ✅ Corregido — causa raíz real: `Navigator.pop(context)` con el `context` externo en vez del del diálogo (`ShellRoute` + navegador anidado), hacía *pop* de la pantalla de fondo en vez del diálogo (sección 3.4d, verificado con reproducción en vivo). Además: `NoteOptionCatalogItem.fromJsonOrNull()` descarta filas de `note_option_catalog` malformadas sin lanzar (3.4c), y `ErrorWidget.builder` global muestra error+stack ante cualquier excepción de build no prevista |
| Borrado de conceptos del catálogo (además de activar/desactivar) | ✅ Completo — `DataRepository.deleteNoteOption()` + ícono de borrar (`Icons.delete_outline`) junto al switch de cada concepto, con diálogo de confirmación; RLS `note_option_catalog_admin_delete` (migración 0011) ya lo permitía. No afecta el historial: las notas ya guardadas conservan el texto del concepto, no una referencia (ver sección 3.4e) |
| Rol **master** (administrador de plataforma) | ✅ Completo en rama `feat/master-role`, **no fusionado a `main` todavía**: migración `0012_master_role.sql` (versionada, **NO aplicada** en Supabase real — aplicación manual pendiente por Carlos), pantalla `PlatformHomeScreen` (Organizaciones/Personal/Sitios/Catálogo con selector de centro), ruta `/platform`, nav exclusiva "Plataforma"+"eKare" para este rol. El master administra ESTRUCTURA de TODOS los centros pero **nunca** ve datos clínicos de pacientes de otras organizaciones (ver sección 5.4) |
| **Volumen por fórmula de Kundin (editable) + gráficas de volumen/composición del tejido** | ✅ Completo en rama `feat/volume-kundin-charts`, **no fusionado a `main` todavía**: `volume_cm3` se auto-calcula (`Largo × Ancho × Profundidad × 0.327`) en captura inicial y seguimiento, permanece editable, y se marca `volume_manual=true` (anotación "✎ Volumen ajustado manualmente" en captura, detalle de consulta y tooltip de gráfica) si el clínico lo sobrescribe; heridas superficiales (profundidad 0/nula) nunca fuerzan un valor. Migración `0015_wound_measurements_volume_manual.sql` (versionada, **NO aplicada** en Supabase real — aplicación manual pendiente por Carlos, antes de cualquier rebuild de producción). Tablero de seguimiento agrega gráfica de volumen en el tiempo y gráfica de composición del tejido (granulación/esfacelo/necrosis/epitelización) en el tiempo, ambas nuevas y additivas — la gráfica de área existente no se modificó. No cambia lógica del motor de reglas (`rulesVersion` sin cambios) (ver sección 3.4f) |

**Conclusión:** el proyecto es una **demo funcional local-first completa y navegable**, con el motor clínico 100% probado y el esquema de base de datos listo para desplegar. Para pasar de *demo* a *piloto* clínico real, lo no negociable es: (1) conectar un proyecto Supabase real con RLS activo y persistencia multiusuario, y (2) subir fotos reales al bucket de storage. Ver sección 9 (Roadmap).

---

## 2. Arquitectura y stack

- **Frontend/App**: Flutter 3.27 (Dart), Material 3, tema claro de marca. Una sola base de código para Web, Android e iOS.
- **Gestión de estado**: Riverpod (`flutter_riverpod`).
- **Navegación**: `go_router`, con `ShellRoute` para el layout con barra lateral/inferior según rol.
- **Backend elegido**: **Supabase** (Postgres + Auth + Storage + Row Level Security), sobre Firebase, porque:
  - El modelo de datos es fuertemente relacional (paciente → herida → evaluación → medición → tratamiento → recomendación), con múltiples FKs y reglas de integridad — Postgres/SQL es más natural que un modelo documental.
  - RLS de Postgres permite expresar de forma declarativa y auditable la regla "personal solo ve sus pacientes asignados", con políticas por tabla en lugar de lógica de filtrado repetida en cada query del cliente.
  - Triggers SQL nativos permiten folios automáticos (`K2024-0001`, `EXP2025-0001`, `PA2026-0001`) y bitácora de auditoría genérica sin código adicional en la app.
  - Storage S3-compatible con políticas RLS sobre `storage.objects` cubre el requisito de evidencia fotográfica por herida con el mismo modelo de permisos que las tablas.
- **Persistencia actual (modo demo)**: `SharedPreferences` como almacén de documentos JSON (`LocalStore`), con colecciones que son un espejo 1:1 de las tablas SQL. Se eligió esto sobre `sqlite-wasm` en Flutter Web para evitar complejidad de compilación adicional en esta fase; es un adaptador temporal, no la arquitectura final.
- **Motor Kura+**: paquete Dart puro (`lib/engine/`), sin dependencias de Flutter, cargado desde JSON de assets versionados (`kura_model_v2.json`, `kura_clinical_adjustments.json`). Esto permite mantenerlo también offline y reutilizar exactamente la misma lógica en pruebas automatizadas.
- **PDF**: paquetes `pdf` + `printing`.
- **Gráficas**: `fl_chart` (tendencia de área de herida en seguimiento).
- **Voz**: `speech_to_text` para dictado en campos de tratamiento.
- **Mapa corporal**: `CustomPainter` propio (sin dependencias SVG de licencia incierta).

---

## 3. Funcionalidades completadas

### 3.1 Motor "Protocolo Kura+" (diferenciador central, función premium)
Ubicación: `lib/engine/`. Orquestado por `KuraProtocolEngine`.

- **8.1 — Modelo de pronóstico**: regresión multinomial 3 clases (A/B/C) con coeficientes exactos cargados desde `assets/engine/kura_model_v2.json`. Pipeline: `z = (x - mean) / scale` → `score = intercept + Σ(coef · z)` → softmax numéricamente estable (resta del máximo antes de exponenciar).
- **8.2 — Ajustes clínicos**: perfusión (ABI/ITB) y nutrición (albúmina) se suman como términos en log-odds **antes** del softmax, con pesos exactos de `assets/engine/kura_clinical_adjustments.json` (no calibrados con datos, tal como se especificó).
- **8.3 — Escenarios**: A (cierre rápido, fenotipo A1), B (cierre asistido, A2–A3), C (no cierre, A4), cada uno con metadatos de fenotipo clínico y comercial (`KuraScenarioLabel`).
- **8.4 — Motor de reglas de tratamiento determinístico** (`kura_treatment_rules_engine.dart`): limpieza siempre incluida; desbridamiento condicional con **regla de seguridad crítica: nunca desbridar si ABI < 0.5**; relleno, apósito absorbente y antimicrobiano según exudado/infección; educación al paciente/cuidador; reglas específicas por etiología (pie diabético, vascular, quirúrgica, traumática); interconsultas automáticas (incluye WUWHS G4 → interconsulta urgente).
- **8.5 — Checkpoint de seguimiento (regla de Sheehan)** (`kura_sheehan_checkpoint.dart`): tabla oficial de umbrales de reducción de área por semana (2/4/6/8; semana 4 validada en 50%/30%), interpolación lineal para semanas intermedias, penalizaciones por infección activa, baja adherencia, deterioro del lecho o aumento de exudado.
- **Versionado explícito**: cada `KuraEngineOutput` incluye `modelVersion`, `adjustmentsVersion` y `rulesVersion` — es un servicio versionado, no lógica oculta.
- **Trazabilidad de decisión clínica**: `ClinicianDecision` (pendiente/aceptada/editada/rechazada) se persiste junto con la recomendación cuando el clínico interactúa con la sugerencia.

**Pruebas** (`test/engine/`, 42/42 pasando):
- Paridad numérica exacta contra referencia Python independiente (5 escenarios clínicos distintos).
- Casos límite: área = 0, comorbilidades no evaluadas, ausencia de ABI/albúmina, extremidad no inferior, softmax estable con scores extremos.
- Reglas de seguridad: ABI < 0.5 nunca genera desbridamiento; WUWHS G4 siempre genera interconsulta urgente.
- Checkpoint Sheehan: umbrales oficiales, interpolación, decisiones, penalizaciones, área basal = 0, empeoramiento.

### 3.2 Modelo de datos e interoperabilidad
- Folios automáticos: personal `K{año}-NNNN`, pacientes `EXP{año}-NNNN` / `PA{año}-NNNN`.
- Entidades completas: Paciente/Expediente, Personal sanitario, Consulta, Herida, Evaluación, Medición seriada, Evidencia fotográfica (límite 17 MB/lote), Tratamiento/Abordaje, Recomendación Kura+.
- Import CSV con mapeo configurable de columnas (pantalla de previsualización) y Export CSV/PDF, pensado como puente de migración desde eKare.

### 3.3 Flujo de captura de heridas (rediseñado, mismo inventario clínico)
Pantallas en `lib/features/wound_capture/`. Conserva los 3 pasos clínicos originales (encabezado de consulta → datos generales/localización → evaluación + medición → abordaje), con:
- **Foto-primero**: sección de evidencia fotográfica como primer bloque visible.
- **Selector de ubicación con mapa corporal** interactivo (silueta dibujada con `CustomPainter`, no dropdown).
- **Divulgación progresiva por etiología**: solo se muestran los campos de Wagner+WIFI (pie diabético), CEAP (venosa), WUWHS (quirúrgica) o agente causal (traumática) según la etiología seleccionada.
- **Pronóstico en vivo**: panel lateral/superior que recalcula probabilidades A/B/C mientras el clínico captura datos (`LivePrognosisPanel`), con la etiqueta de apoyo a decisión clínica siempre visible.
- **Sliders de composición del lecho** con validación de suma = 100 % (`BedCompositionSliders`).
- **Menos fricción**: valores por defecto sensatos y guardado de borrador de consulta.
- **Dictado por voz** disponible en el paso de tratamiento.
- **Modo offline**: toda la captura funciona sin conexión sobre el almacén local.

### 3.4 Seguimiento comparativo (100% derivado de la serie real)
`lib/features/follow_up/follow_up_screen.dart` + `lib/features/follow_up/follow_up_capture_screen.dart`.

- **Registrar seguimiento**: botón en el AppBar de la pantalla de seguimiento abre `FollowUpCaptureScreen`, un formulario que crea una consulta `visit_type='seguimiento'` ligada a la herida y persiste en Supabase: nueva fila en `wound_measurements` (largo/ancho→área, profundidad, composición del lecho con los mismos `BedCompositionSliders` de la captura inicial), estado clínico en `wound_assessments` (infección IWII, exudado, adherencia al tratamiento — nuevo campo `low_adherence`), y foto "actual" en `wound_photos` vía `PhotoUploadService`. No hace INSERT directo a `audit_log` (el trigger existente ya audita `wound_measurements`; `wound_assessments`/`wound_photos` no están en su alcance por diseño).
- **Gráfica de tendencia de área**: grafica *todas* las mediciones de la herida ordenadas por `measured_at` — un punto por visita (basal = primera, una por cada seguimiento), nunca solo basal-vs-actual.
- **Checkpoint de Sheehan**: se recalcula basal vs. medición más reciente contra el umbral de la semana correspondiente. Si solo existe la valoración basal (0 seguimientos), se muestra un estado vacío explícito ("Aún sin seguimientos") en vez de comparar la basal contra sí misma. Las tablas de umbrales oficiales (`KuraSheehanCheckpoint._umbralesOficiales`) son constantes legítimas del protocolo y no se tocan.
- **Penalizaciones cableadas a datos reales**: la evaluación clínica (`wound_assessments`) de la visita más reciente (empatada por `consultation_id` con la medición más reciente) alimenta `bajaAdherencia` (definitivo, campo `low_adherence`) e `infeccionActiva` (proxy INTERINO — pendiente de validar con la Dra. Capistrán la representación/umbral oficial de IWII: hoy es "cualquier criterio marcado"). `deterioroDelLecho` y `aumentoDeExudado` quedan en `false` a propósito: requieren una regla comparativa visita-actual-vs-anterior aún sin definir, no inventada por el agente. Cuando hay penalizaciones, el tablero muestra el `%` bruto y el `%` ajustado por separado, más chips con cada penalización aplicada (p. ej. "Baja adherencia al tratamiento −5 pp"); el gauge de decisión usa el % ajustado (el que realmente decide contra los umbrales).
- **Fotos "basal"/"actual"**: son la `wound_photo` más antigua y la más reciente (por `taken_at`) de la herida, resueltas vía `PhotoUploadService.resolveDisplayUrl` (URL firmada en Supabase real, o data-URL en modo demo). Si no hay fotos, se muestra un placeholder explícito, nunca una imagen de ejemplo.

### 3.4f Volumen por fórmula de Kundin (editable) + gráficas de volumen y composición del tejido — rama `feat/volume-kundin-charts`

**Cálculo automático (fórmula de Kundin, elegida explícitamente sobre π/6≈0.5236)**: `lib/core/utils/wound_volume.dart` (`WoundVolumeCalculator`) implementa `volume_cm3 = lengthCm × widthCm × depthCm × 0.327`. Se recalcula en vivo en ambas pantallas de captura (`wound_capture_screen.dart` para valoración inicial y `follow_up_capture_screen.dart` para seguimiento, reutilizando el mismo `_volumeCtrl` existente en esta última, sin campo duplicado) cada vez que cambian Largo/Ancho/Profundidad, únicamente cuando la herida es profunda (`depthCm >= 0.5`, mismo umbral que `isDeepWound` en ambos formularios). Si la profundidad es 0 o nula, el volumen es `null`/"N/A" — nunca se fuerza un valor (semántica clínica distinta a "no medido todavía").

**Campo editable con detección de ajuste manual**: patrón "auto-following" por bandera de estado (`_volumeAutoFollowing`) — el campo se sobreescribe con el valor auto-calculado mientras el clínico no lo edite a mano; en cuanto lo edita se detiene el auto-seguimiento (se reanuda si borra el campo). Al guardar, `volume_manual` **no es un toggle persistido manualmente**: se deriva comparando el valor guardado contra el recién recalculado por Kundin con tolerancia 0.01 cm³ (`WoundVolumeCalculator.isManualOverride`), evitando falsos positivos por redondeo flotante. Cuando `volume_manual=true` se muestra la anotación "✎ Volumen ajustado manualmente" en tres lugares: (1) la propia pantalla de captura, (2) `consultation_detail_screen.dart` (detalle de consulta, solo lectura), y (3) el tooltip + punto resaltado de la gráfica de volumen en `follow_up_screen.dart`.

**Migración `0015_wound_measurements_volume_manual.sql`** (additiva, `add column if not exists`): agrega `wound_measurements.volume_manual boolean not null default false` — `volume_cm3` ya existía desde la migración `0008`. **⚠️ Pendiente de aplicación manual por Carlos en el SQL Editor de Supabase real, ANTES de cualquier rebuild de producción/demo** (mismo orden de despliegue que `0013`/`0014`). El modelo `WoundMeasurement` (`lib/models/wound.dart`) ya lee/escribe `volumeManual` en `fromJson`/`toJson`.

**Gráficas nuevas en el tablero de seguimiento** (`follow_up_screen.dart`, ambas additivas — la gráfica de tendencia de área existente no se tocó):
- **Volumen en el tiempo**: `LineChart` (fl_chart) graficando `volume_cm3` por visita, omitiendo con gracia las visitas sin medición de volumen (herida superficial en esa visita); si la herida no tiene ninguna medición de volumen en toda su serie, se muestra el placeholder "Sin mediciones de volumen (herida superficial: no se activa la medición 3D)." en vez de una gráfica vacía. Los puntos con `volume_manual=true` se resaltan visualmente (color/tamaño distinto) y su tooltip incluye la anotación de ajuste manual.
- **Composición del tejido en el tiempo**: `LineChart` con 4 series (granulación/esfacelo/necrosis/epitelización, `%`) por visita, con leyenda de color por serie.

**Verificación**: 15 tests nuevos en `test/unit/wound_volume_test.dart` (fórmula de Kundin, detección de ajuste manual con tolerancia, round-trip `WoundMeasurement.volumeManual` incluyendo heridas superficiales y filas legacy sin la columna). `flutter analyze`/`flutter test` (150/150) /`build_gate.sh` verdes. **Estado de rama**: todo el trabajo vive en `feat/volume-kundin-charts` (no en `main`), pendiente del visto bueno explícito del usuario para el merge — no cambia lógica del motor de reglas, por lo que `rulesVersion` no se incrementa.

### 3.5 Detalle de consulta (solo lectura)
`lib/features/consultation/consultation_detail_screen.dart`. Cada ítem del historial de consultas en `patient_detail_screen.dart` es tappable y navega a esta pantalla, que muestra —solo lectura, respetando RLS— todo lo registrado en esa consulta: datos generales (fecha, tipo de visita, sitio, personal sanitario), la(s) herida(s) evaluada(s) en la consulta y su evaluación (mediciones, composición del lecho, exudado, infección, borde, piel perilesional), la recomendación Kura+ emitida si la hubo (escenario A/B/C, fenotipo comercial, régimen, interconsultas), el tratamiento aplicado y las fotos tomadas en esa visita. Como `wounds` no tiene FK directa a `consultations`, la asociación herida↔consulta se infiere del lado del cliente revisando qué mediciones/evaluaciones de cada herida tienen ese `consultation_id`. El **tipo de exudado** (`exudate_type`) ahora se lee y muestra correctamente aquí — `WoundAssessment.fromJson()`/`toJson()` lo parsean y persisten (antes se perdía en el round-trip y siempre aparecía vacío).

### 3.6 Reportes
`lib/features/reports/reports_screen.dart`: selección múltiple de pacientes, filtros (consultas/seguimientos/antecedentes/evidencias — todas o primera/última), botón de generación de PDF.

### 3.6 Roles y administración
- **Administrador**: gestiona personal (alta con folio automático), sitios, pacientes, catálogo de la nota de seguimiento, y activa función premium por usuario. El administrador **pertenece a un centro (organización)** y solo ve/gestiona personal, sitios, pacientes y catálogo de SU organización.
- **Personal sanitario/clínico**: solo ve pacientes que le fueron asignados (`staff_patient_assignments`); puede operar en TODOS los sitios del centro al que pertenece (no está restringido a un `primary_site_id`, que queda solo como valor por defecto opcional al crear una consulta).
- **Admin sin ficha de personal (licencia individual)**: si el administrador de un centro nuevo aún no tiene una fila en `staff` (p. ej. porque se dio de alta directamente como admin), el sistema le crea una de forma automática y transparente la primera vez que la necesita (login o alta de consulta), para que pueda registrar consultas y que los pacientes que da de alta se le auto-asignen como a cualquier otro miembro del personal — ver sección 5.3, ajuste #3.
- Pantalla `lib/features/admin/admin_home_screen.dart` con pestañas Usuarios / Personal / Sitios / Catálogo de notas.

### 3.4b Catálogo de la nota de seguimiento: alta manual + import/export CSV
`lib/features/admin/admin_home_screen.dart` (`_NoteCatalogTab`). El admin configura, por cada una de las 4 secciones (tipo de atención, descripción de procedimiento, material utilizado, evolución), los conceptos que el personal clínico ve como chips al capturar una nota de seguimiento (`follow_up_capture_screen.dart`).
- **Alta manual**: botón flotante "Nuevo concepto" (`_addOption()`/`_promptForLabel()`), sin cambios respecto a versiones anteriores.
- **Descargar plantilla CSV**: botón que exporta las 4 secciones del catálogo actual del centro en un CSV con columnas `seccion,concepto,activo` (`_downloadTemplate()`), pensado para editarse en Excel/Sheets y volver a cargarse.
- **Cargar CSV**: botón que permite seleccionar un archivo CSV (mismas columnas) y hace un **merge en bloque** de las 4 secciones a la vez (`DataRepository.bulkImportNoteOptions`): valida sección/concepto, agrega los conceptos nuevos, actualiza el estado activo/inactivo de los existentes, y omite filas inválidas o sin cambios. Al finalizar muestra un diálogo con el **resumen de importación** (agregados/actualizados/omitidos, con detalle de errores si los hubo).
- Ambas rutas (manual y CSV) están siempre disponibles y coexisten; todo queda **scoped al `organization_id`** del centro del admin, y solo el rol admin puede escribir en el catálogo (RLS `is_admin()`).

### 3.4c Fix: pantalla en blanco al crear concepto de catálogo (bug reportado contra Supabase real)
**Síntoma reportado**: Administración → Configuración → seleccionar campo → FAB "Nuevo concepto" → escribir texto → "Guardar" → pantalla en blanco, sin SnackBar de error.

**Diagnóstico (evidencia real, no especulativa)**: `test/unit/note_catalog_blank_screen_repro_test.dart` reproduce con el motor real de Dart (stack traces reales capturados en la ejecución) el mecanismo exacto:
- `_NoteCatalogTabState._addOption()` envuelve en `try/catch` únicamente el `await widget.repo.createNoteOption(...)`. Si esa llamada falla (p.ej. hipótesis del hueco de RLS `insertRow().select().single()` sin fila visible tras el INSERT), la excepción **sí** cae en el catch → SnackBar. Esta hipótesis, aislada, **no** explica el síntoma reportado (ausencia de SnackBar) — se descarta como causa única mediante un test que reproduce ese `PostgrestException` y confirma que es capturable.
- El punto que **sí** reproduce el síntoma exacto: tras el `setState()` (ya con el insert exitoso), `_NoteCatalogTabState.build()` llama `widget.repo.listAllNoteOptions(_selectedField)` **sin try/catch**. Ese método mapeaba **toda** la colección cacheada de `note_option_catalog` con `NoteOptionCatalogItem.fromJson()`, que hace *casts* no-nulos de `id`/`label`. Si **cualquier** fila ya presente en caché (no necesariamente la recién creada) tiene `id` o `label` nulo, se lanza un `TypeError` de cast **fuera** del alcance del try/catch de `_addOption()` → en Flutter Web release esto se traduce en una pantalla en blanco silenciosa (el `ErrorWidget` por defecto es casi invisible), exactamente el síntoma reportado. Confirmado con stack trace real de Dart (no simulado) en el test citado.
- **Nota de alcance**: esta corrección resuelve el mecanismo confirmable sin acceso a producción (fila cacheada malformada). No descarta que en el entorno Supabase real del cliente exista *además* un problema de RLS/`organization_id` (hipótesis (a) del reporte); esa parte requiere el stack trace real capturado en la consola del navegador contra producción, que no pudo obtenerse desde este sandbox (sin credenciales de Supabase real disponibles). El hardening del punto siguiente cubre ese caso: si vuelve a ocurrir cualquier excepción de build no prevista, ahora se muestra en pantalla en vez de quedar en blanco.

**Fix aplicado**:
- `NoteOptionCatalogItem.fromJsonOrNull()` (`lib/models/note_option_catalog.dart`): variante tolerante que valida cada campo por tipo real (`is`, no `as`) y devuelve `null` en vez de lanzar ante una fila malformada.
- `DataRepository.listNoteOptions()`/`listAllNoteOptions()` (`lib/services/data_repository.dart`): usan `fromJsonOrNull` + `whereType<NoteOptionCatalogItem>()`, descartando en silencio filas corruptas sin tumbar el listado ni la pantalla.
- **Hardening global** (`lib/main.dart`): `ErrorWidget.builder` reemplazado para que cualquier excepción de `build()` en cualquier pantalla de la app muestre un mensaje de diagnóstico (excepción + stack trace, seleccionable) en el lugar del árbol de widgets donde ocurrió, en vez de una pantalla en blanco — en debug y en release. Esto no sustituye la consola del navegador para depuración exhaustiva, pero evita que un fallo similar (o distinto, no cubierto por el fix anterior) vuelva a manifestarse como pantalla en blanco sin ningún texto visible.
- Cobertura: 6 tests nuevos en `test/unit/note_catalog_blank_screen_repro_test.dart` (58/58 en la suite completa), incluyendo el caso "antes del fix" (reproduce el `TypeError` real) y "después del fix" (confirma que se descarta la fila corrupta sin lanzar).

### 3.4d Causa raíz real de la pantalla en blanco: `Navigator.pop(context)` con el `context` equivocado en diálogos anidados en `ShellRoute`
**El fix de 3.4c era correcto pero no era la causa de este bug.** Se confirmó mediante reproducción en vivo (Playwright, contra este mismo sandbox) que la pantalla en blanco ocurre **también** al pulsar "Cancelar" en el diálogo "Nuevo concepto" — un camino de código que nunca llama a `createNoteOption()`, `listAllNoteOptions()` ni `fromJson()`, por lo que el mecanismo de 3.4c queda descartado como causa de *este* síntoma específico.

**Causa raíz real**: la app usa `ShellRoute` (go_router) con navegador anidado. `showDialog()` empuja el diálogo en el **Navigator raíz** por defecto, pero varios diálogos hacían `builder: (_) => AlertDialog(... onPressed: () => Navigator.pop(context) ...)`, reutilizando el `context` **externo** (el de la pantalla que abrió el diálogo) en vez del `context` que el propio `builder` recibe para el diálogo. Al pulsar cualquier botón del diálogo, el `Navigator.of(context)` resuelto con ese `context` externo termina haciendo *pop* de la ruta de fondo (la del `ShellRoute`/pantalla) en lugar de cerrar el diálogo — dejando el árbol de widgets de la pantalla desmontado sin ruta visible detrás. No se lanza ninguna excepción de Dart (por eso `ErrorWidget.builder` nunca se activa y no hay stack trace en consola): es un *pop* válido, solo que del navegador equivocado.

**Evidencia de reproducción y verificación** (Playwright, `/tmp/repro_test/`, no versionado): antes del fix, tras cerrar el diálogo (con "Cancelar" **o** "Guardar") el `<canvas>` de CanvasKit dentro del shadow DOM de `flt-glass-pane` pasaba de 1 elemento (1280×800, visible) a **0 elementos**, sin recuperación tras 30s de espera ni tras interacción/resize/renavegación — consistente con que la ruta que contenía el `Scaffold` de `_NoteCatalogTab` fue desmontada por el `pop` erróneo. Después del fix: el canvas se mantiene en 1 en todo momento, el diálogo cierra correctamente con ambos botones, y el concepto nuevo aparece en la lista tras "Guardar".

**Fix aplicado** — nombrar el `context` del `builder` y usarlo (no el externo) en cada `Navigator.pop` dentro de ese mismo diálogo:
- `lib/features/admin/admin_home_screen.dart`: diálogo "Resumen de importación" (~L806/824) y `_promptForLabel` (~L979/988/992).
- `lib/features/import_export/import_export_screen.dart`: diálogo "Exportación CSV generada" (~L72/79).
- `_StaffFormDialog`/`_SiteFormDialog` **no** requerían cambio: son `StatefulWidget`s independientes cuyo `Navigator.pop(context, ...)` ya usa el `context` propio de ese diálogo (heredado de su propio `State`), no uno capturado desde afuera.
- Patrón aplicado: `builder: (dialogCtx) => AlertDialog(..., onPressed: () => Navigator.pop(dialogCtx[, valor]))`.
- Verificado con `flutter analyze` (0 errores), `flutter test` (58/58) y reproducción en vivo post-fix (Playwright): el bug ya no ocurre con "Cancelar" ni con "Guardar".

### 3.4e Borrado de conceptos del catálogo (junto al switch activar/desactivar)
`_NoteCatalogTab`/`_NoteCatalogTabState` (`lib/features/admin/admin_home_screen.dart`) y `DataRepository.deleteNoteOption()` (`lib/services/data_repository.dart`). Hasta ahora cada concepto del catálogo solo podía activarse/desactivarse (`Switch`); se agregó la posibilidad de borrarlo definitivamente.

- **`DataRepository.deleteNoteOption(String id)`**: delega en `_store.deleteRow(Collections.noteOptionCatalog, id)` (mismo patrón que el borrado de `Collections.treatmentComponents`). En producción, la política RLS `note_option_catalog_admin_delete` (migración `0011_organizations.sql`) ya restringe el `DELETE` a admins de la misma organización; no se requirió ningún cambio de migración.
- **UI**: cada `ListTile` de la lista de conceptos ahora tiene, en `trailing`, un `Row` con un `IconButton` (`Icons.delete_outline`, color `KuraColors.danger`) seguido del `Switch` existente. Al pulsar el ícono se muestra un diálogo de confirmación ("¿Borrar este concepto? No afecta las notas ya guardadas.") con botones "Cancelar"/"Borrar"; solo si se confirma se llama a `deleteNoteOption` + `setState`, todo envuelto en `try/catch` con `SnackBar` en caso de error (mismo estilo que `_toggleActive`).
- **Diálogo construido con el patrón correcto (ver 3.4d)**: `builder: (dialogCtx) => AlertDialog(...)` y `Navigator.pop(dialogCtx, ...)` en ambos botones — evita reintroducir la pantalla en blanco por reutilizar el `context` externo de `_NoteCatalogTab` en el `pop`.
- **Nota de diseño (no afecta el historial)**: `Consultation.followUpMaterialsUsed`/`followUpCareType`/etc. (`lib/models/consultation.dart`) guardan el **texto** del concepto elegido al capturar la nota, no una referencia (FK) al `id` de `note_option_catalog`. Por lo tanto, borrar un concepto del catálogo solo lo quita de las opciones futuras (chips al capturar una nueva nota); las notas de seguimiento ya guardadas conservan el texto tal cual y no se ven afectadas. Verificado con un test de integración real (no solo documentado): se crea un concepto, se usa su label al crear una consulta, se borra el concepto del catálogo, y se confirma que la consulta ya guardada sigue teniendo el mismo texto.
- **Cobertura**: 3 tests nuevos en `test/unit/note_catalog_delete_test.dart` (61/61 en la suite completa) — borrar quita el concepto del listado sin afectar a los demás del mismo campo, no afecta a conceptos de otros campos, y no afecta el texto de consultas históricas que ya usaron ese concepto.
- Verificado también con reproducción en vivo (Playwright contra este sandbox): el ícono de borrar aparece en cada fila, el diálogo de confirmación muestra el texto exacto esperado, "Cancelar" no borra nada y no produce pantalla en blanco, y "Borrar" elimina el concepto de la lista sin pantalla en blanco (`<canvas>` de CanvasKit se mantiene presente en todo momento).

### 3.7 Marca visual
`lib/core/theme/kura_theme.dart`: magenta/rojo `#EC0244`, texto oscuro `#211813`, fondo claro `#FBF5EC`, tipografía Nunito (vía `google_fonts`).

---

## 4. Rutas de la aplicación

Definidas en `lib/core/router/app_router.dart` (GoRouter):

| Ruta | Pantalla | Notas |
|---|---|---|
| `/login` | Login | Lista de cuentas demo clicables (ver sección 6) |
| `/` | Dashboard | Redirige a `/login` si no hay sesión |
| `/patients` | Listado de pacientes | |
| `/patients/new` | Alta de paciente | Folio automático EXP/PA |
| `/patients/:patientId` | Detalle de paciente | Heridas con badge de escenario Kura+ |
| `/patients/:patientId/consultation/new` | Encabezado de consulta | Fecha/sitio/tipo de visita |
| `/patients/:patientId/wound/:woundId/capture?consultationId=` | Captura de herida | `woundId` opcional (nueva herida) |
| `/patients/:patientId/wound/:woundId/follow-up` | Seguimiento | Gráfica + Sheehan, 100% derivado de la serie real |
| `/patients/:patientId/wound/:woundId/follow-up/new` | Registrar seguimiento | Formulario de nueva visita de seguimiento |
| `/patients/:patientId/consultation/:consultationId` | Detalle de consulta | Solo lectura, accesible desde el historial del paciente |
| `/reports` | Reportes | Generación de PDF |
| `/admin` | Administración | Solo rol admin |
| `/platform` | Plataforma | Solo rol master — gestión de organizaciones/sitios/personal/catálogo de todos los centros (ver sección 5.4). Rama `feat/master-role` |
| `/import-export` | Import/Export CSV | Interoperabilidad eKare |

---

## 5. Modelo de datos y almacenamiento

### 5.1 Esquema (Supabase / Postgres) — diseñado y desplegado (0001→0010 aplicadas)
`supabase/migrations/`:
- `0001_core_schema.sql` — 17 tablas: `profiles`, `sites`, `staff`, `staff_patient_assignments`, `patients`, `patient_comorbidities`, `consultations`, `wounds`, `wound_assessments`, `wound_measurements`, `perfusion_nutrition_data`, `wound_photos`, `treatment_plans`, `treatment_components`, `kura_recommendations`, `sheehan_checkpoints`, `audit_log`, `import_batches`. Incluye tipos `enum`, constraints `CHECK` (suma de composición del lecho ≤ 100.01) e índices.
- `0002_triggers_and_functions.sql` — folios automáticos, `updated_at`, `audit_trigger_fn()` (SECURITY DEFINER, AFTER INSERT/UPDATE/DELETE en tablas clínicas), `handle_new_auth_user()`, helpers `is_admin()`, `current_staff_id()`, `current_user_role()`.
- `0003_row_level_security.sql` — RLS en todas las tablas clínicas: acceso total para admin, y para personal clínico solo si existe una fila en `staff_patient_assignments` para ese paciente.
- `0004_storage_buckets.sql` — bucket `wound-evidence` (límite 17 825 792 bytes = 17 MB), políticas RLS sobre `storage.objects` basadas en el primer segmento de la ruta (`(storage.foldername(name))[1] = wound_id`).
- `0005_wifi_braden_hba1c.sql` — columnas `braden_score`/`hba1c_pct` en `wound_assessments`.
- `0006_prevent_profile_privilege_escalation.sql` — hardening de RLS en `profiles`.
- `0007_wound_assessment_adherence.sql` — columna `low_adherence boolean not null default false` en `wound_assessments`, para el flag de baja adherencia capturado en el formulario de seguimiento. **Aplicada y verificada contra el proyecto Supabase real del cliente** — `wound_assessments.low_adherence` ya existe en producción y el checkpoint de Sheehan ya la consume (ver sección 3.4).
- `0008_follow_up_protocol_fields.sql` — alineación Prioridad 1 (protocolos clínicos Kura+): `wound_measurements.volume_cm3` (medición 3D, heridas profundas) + `wound_measurements.manual_measurement_note` (socavamiento/tunelización/circunferencial/irregular); `wound_photos.photo_stage` (`antes_limpiar`/`despues_limpiar`/`con_medicion`/`cierre`, Protocolo de Fotografías §1.2); `consultations.follow_up_care_type`/`follow_up_procedure_desc`/`follow_up_materials_used`/`follow_up_evolution`/`follow_up_signed_by`/`follow_up_signed_license` (nota de seguimiento obligatoria, Instructivo de Archivo); `staff.cedula_profesional` (catálogo para prellenar la firma).
- `0009_visit_type_cierre.sql` — agrega el valor `'cierre'` al enum Postgres `visit_type`.
- `0010_note_option_catalog.sql` — tabla `note_option_catalog` (field/label/is_active/created_by) que alimenta los chips de la nota de seguimiento, configurable por el admin del centro. RLS: SELECT para todo el personal autenticado; INSERT/UPDATE/DELETE solo admin (`is_admin()`). Precargada con 23 conceptos base (5 tipo de atención, 6 descripción de procedimiento, 7 material utilizado, 5 evolución). No se audita (catálogo administrativo, no dato clínico de paciente).
- `0011_organizations.sql` — **modelo Centro (organización) → Sitios → Personal** (ver detalle en sección 5.3). ✅ Escrita, versionada y verificada localmente (analyze/test/build); **⚠️ NO aplicada aún** al proyecto Supabase real del cliente — es el único paso manual pendiente (`supabase db push` o SQL Editor) antes de que el aislamiento por organización, en particular la corrección crítica de aislamiento de pacientes, tome efecto en producción.
- `0012_master_role.sql` — rol `master` (ver sección 5.4). Versionada, **NO aplicada aún** en Supabase real.
- `0013_note_option_catalog_kura_tag.sql` / `0014_wound_assessments_clinical_notes.sql` — etiqueta `kura_tag` del catálogo de notas y campo libre de notas clínicas por visita. Rama correspondiente ya fusionada a `main`.
- `0015_wound_measurements_volume_manual.sql` — agrega `wound_measurements.volume_manual boolean not null default false` (ver sección 3.4f). Additiva, `add column if not exists`. Rama `feat/volume-kundin-charts`, versionada, **⚠️ NO aplicada aún** en Supabase real — pendiente de aplicación manual por Carlos antes del rebuild de producción/demo.

**✅ Migraciones `0008`, `0009` y `0010` aplicadas y confirmadas por el cliente contra el proyecto Supabase real** — el flujo de seguimiento refinado (fotos en secuencia, catálogo de conceptos, firma/cédula) ya cuenta con su esquema en producción. **`0011` está pendiente de aplicar** (ver sección 9, paso 0).

### 5.2 Almacenamiento actual (modo demo local-first)
`lib/services/local_db/local_store.dart`: `SharedPreferences` usado como almacén de documentos JSON; `Collections` define nombres de colección que son espejo exacto de las tablas SQL anteriores (incluye ahora `organizations`). `demo_seed.dart` siembra automáticamente, en el primer arranque:
- 1 organización ("Kura+") + 4 sitios (Clínica CDMX, Clínica GDL, Domicilio CDMX, Domicilio GDL), 3 perfiles (1 admin + 2 clínicos), 3 personal sanitario (incluye la fila de `staff` del admin, para reflejar el fix del ajuste #3 también en modo demo).
- 5 pacientes cubriendo las 4 etiologías + un caso de **isquemia crítica** (ABI 0.38) usado como caso de prueba de la regla de seguridad "no desbridar". Todos con `organization_id` de Kura+.
- Comorbilidades, heridas, consultas (incluye seguimientos para graficar tendencia), evaluaciones, mediciones seriadas, datos de perfusión/nutrición y un plan de tratamiento de ejemplo.

**Importante**: hoy no hay sincronización real entre dispositivos ni multiusuario concurrente — cada instancia del navegador/app tiene su propio almacén local. Esto es intencional para la fase de demo, y es el primer punto del roadmap hacia piloto (sección 9).

### 5.3 Modelo Centro (organización) → Sitios → Personal + aislamiento crítico de pacientes

Migración `0011_organizations.sql` introduce el tenant `organizations` (el centro, p. ej. "Kura+") y lo enlaza a las tablas que antes eran de facto globales:

- **`organizations`**: nueva tabla raíz (`id`, `name`, `is_active`, `created_at`). Backfill automático: se crea una organización "Kura+" y se le asignan todas las filas existentes.
- **`sites.organization_id`** (not null): un centro tiene 1→N sitios. El personal puede operar en **todos** los sitios de su centro — `staff.primary_site_id` sigue existiendo solo como valor por defecto opcional al crear una consulta, nunca como límite.
- **`profiles.organization_id`** (not null): fuente de verdad que usa el helper `current_organization_id()` (SECURITY DEFINER, mismo patrón que `is_admin()`/`current_staff_id()`) para resolver la organización del usuario autenticado.
- **`staff.organization_id`** (not null, columna explícita, no solo derivada vía `profile_id`): necesaria para dar soporte a personal administrativo **sin cuenta de acceso** (`profile_id` NULL), que de otra forma no tendría organización resoluble.
- **`note_option_catalog.organization_id`** (not null): el catálogo de conceptos de nota de seguimiento pasa de ser global a **configurable por centro** (uniqueness ahora es `(organization_id, field, label)`).
- **`patients.organization_id`** (not null) — **la corrección crítica**: antes, la política `patients_select` le daba a *cualquier* admin (de cualquier organización) `SELECT` de *todos* los pacientes de la base — un bug de aislamiento multi-tenant grave. La política se reescribe para que un admin vea/edite solo pacientes de **su** organización; un clínico sigue viendo solo los que tiene asignados (`staff_patient_assignments`), asignación que ya queda transitivamente acotada a la organización porque tanto `staff` como `patients` llevan `organization_id` verificado. Las 9 tablas descendientes (`wounds`, `wound_assessments`, `wound_measurements`, `perfusion_nutrition_data`, `wound_photos`, `treatment_plans`, `treatment_components`, `kura_recommendations`, `sheehan_checkpoints`) **no necesitan columna `organization_id` propia**: heredan el aislamiento por FK transitiva hacia `patients` (ya estaban escritas así en `0003_row_level_security.sql`), sin tocar esas 9 tablas.
- **`create_organization_with_admin(p_organization_name, p_admin_full_name)`**: RPC para el flujo de alta de un centro nuevo — crea la organización, promueve el perfil que la invoca a admin y le crea su fila de `staff` correspondiente, en una sola transacción.
- **Fix admin-clínico (licencia individual)**: para el caso de un admin que **ya existía** antes de `0011` (o al que no se le creó `staff` vía el RPC anterior), `DataRepository.ensureAdminStaffId(AppUser adminUser)` busca su fila de `staff` por `profile_id` y, si no existe, la crea de forma perezosa (folio `''`, `role_title: 'Administrador'`). Se ejecuta automáticamente:
  - En `SessionController.login()`/`_restoreSupabaseSession()` (vía `_ensureStaffIdForAdmin()`), de forma transparente en cada inicio de sesión.
  - Como *fallback* redundante directamente en `consultation_hub_screen.dart` y `follow_up_capture_screen.dart`, para no bloquear el registro de una consulta si por algún motivo (p. ej. falla de red durante el login) la provisión a nivel de sesión no se completó.
  - Una vez resuelto el `staffId`, el auto-asignado de pacientes al personal que los registra (código ya existente) funciona igual para el admin que para cualquier clínico.

**Pendiente manual**: la migración `0011` está completa, versionada y verificada localmente, pero **debe aplicarse al proyecto Supabase real del cliente** (`supabase db push` o SQL Editor, ver sección 9) para que el aislamiento de pacientes y el resto del modelo tomen efecto en producción — mientras no se aplique, producción sigue en el comportamiento anterior a `0011`.

### 5.4 Rol `master` (administrador de plataforma) — rama `feat/master-role`

Migración `0012_master_role.sql` (versionada, **⚠️ NO aplicada aún** en Supabase real — paso manual pendiente por Carlos, igual que `0011`) agrega el rol `master`, pensado para quien administra la plataforma multi-centro completa (Kura+ como proveedor), no un centro en particular.

**Regla de oro (no negociable)**: el master administra ESTRUCTURA — `organizations`, `sites`, `staff`, `note_option_catalog` — de **todos** los centros, y puede crear centros/sitios nuevos. El master **NUNCA** tiene acceso a datos clínicos de pacientes (`patients`, `wounds`, `wound_assessments`, mediciones, fotos, etc.) de ninguna organización: las políticas RLS de esas tablas (0011) no se tocaron. `is_master()` (mismo patrón `SECURITY DEFINER` que `is_admin()`) se agrega con `or public.is_master()` **sin filtro de organización** únicamente en las 4 tablas estructurales; el trigger `prevent_profile_privilege_escalation` se actualiza con `and not public.is_master()` para no bloquear al master en su propia fila de `profiles`.

**Bootstrap del primer master (manual, una sola vez)**: no hay flujo de alta desde la UI por diseño (evita que cualquier admin se autopromueva). En el SQL Editor de Supabase, tras crear el usuario en Auth normalmente:
```sql
update profiles set role = 'master' where email = '<email-del-primer-master>';
```

**App (Flutter)**: `AppRole.master`/`isMaster` en `AppUser`/`SessionState`; pantalla `PlatformHomeScreen` (`lib/features/platform/`) con 4 pestañas — Organizaciones (listar/crear/activar centros) y, dentro de un centro elegido en el selector, Personal sanitario/Sitios/Catálogo — **reutilizando** los widgets `StaffTab`/`SitesTab`/`NoteCatalogTab` ya existentes de `admin_home_screen.dart` (hechos públicos y parametrizados con un `organizationId` opcional, en vez de duplicar CRUD). Ruta `/platform`; el router redirige a un master que inicia sesión (o que de alguna forma llega a `/`) directamente a `/platform`, porque no tiene dashboard/pacientes/reportes propios; la navegación lateral/inferior (`AppShell`) le oculta por completo Inicio/Pacientes/Reportes/Administración y solo le muestra "Plataforma" y "eKare".

**Verificación realizada** (sandbox de desarrollo, backend demo local — sin credenciales de Supabase real):
- `flutter analyze`: 0 errores. `flutter test`: **67/67 tests pasando**, incluyendo 6 tests nuevos en `test/unit/master_role_test.dart` (creación/listado de organizaciones, y que `listSites`/`listStaff`/`listAllNoteOptions` con `organizationId` acotan estrictamente al centro indicado sin mezclar datos de otro centro).
- `flutter build web --release`: exitoso. Verificación E2E en vivo (Playwright contra este sandbox) con la cuenta demo `master@kuratracker.mx`: login redirige a `/platform`, nav lateral muestra solo Plataforma/eKare, pestaña Organizaciones lista los 2 centros del seed demo (Kura+ y Clínica Vitalis) con switch activo/inactivo y botón "Nuevo centro", y las pestañas Personal sanitario/Sitios/Catálogo respetan el selector de centro (el personal/sitios de un centro no aparecen al filtrar por el otro).
- **Bug real encontrado y corregido durante esta verificación**: `_StaffTabState.build()` (`admin_home_screen.dart`) hacía `s.folio.substring(1, 3)` para el avatar; un `staff` con folio `''` (alta administrativa sin folio automático, p. ej. el admin sembrado de Clínica Vitalis) lanzaba `RangeError` y tumbaba toda la pestaña "Personal sanitario" con cualquier organización que tuviera ese caso. Se corrigió con un fallback seguro (inicial del nombre) cuando el folio es muy corto; re-verificado con captura de pantalla mostrando la pestaña cargando correctamente.
- **Pendiente de verificar contra Supabase real** (requiere que Carlos aplique `0011`+`0012` primero, ver paso 0 de la sección 9): la prueba negativa de privacidad (que un master autenticado, vía REST directo con su JWT, reciba 0 filas al pedir `patients`/`wound_assessments` de cualquier organización) no pudo ejecutarse en este sandbox por no haber credenciales de un proyecto Supabase real disponibles; queda como paso de aceptación manual antes de dar por cerrado el rol en producción.
- **Estado de rama**: todo el trabajo del rol master vive en la rama `feat/master-role` (no en `main`), por instrucción explícita del usuario, hasta que se confirme el resultado de `flutter test`/`flutter build web` (ya verde) — el merge/PR a `main` queda pendiente de que el usuario lo confirme.

---

## 6. Guía de usuario (demo)

1. Abrir la URL del demo (sección 7).
2. En la pantalla de login, hacer clic sobre cualquiera de las **cuentas de demostración** listadas (no se valida contraseña real en este modo):
   - **Administrador Procomsa** (`admin@curamas.mx`) — rol admin, premium activo.
   - **Dra. Ana Martínez** (`ana.martinez@curamas.mx`, folio `K2024-0001`) — clínico, premium activo, ve pacientes 1, 2, 3 y 4.
   - **Lic. Carlos Ramírez** (`carlos.ramirez@curamas.mx`, folio `K2024-0002`) — clínico, sin premium, ve pacientes 4 y 5.
3. Desde el Dashboard o `/patients`, seleccionar un paciente para ver su expediente y heridas.
4. Para capturar una nueva consulta/herida: **Nueva consulta** → completar encabezado → **Continuar** hacia captura de herida → seleccionar etiología y ubicación en el mapa corporal → completar evaluación (los campos cambian según etiología) → ajustar sliders de composición del lecho → observar el **panel de pronóstico en vivo** actualizarse.
5. Al continuar a tratamiento: si la cuenta tiene premium, activar **"Utilizar protocolo Kura+"** para prellenar el régimen sugerido (editable); se registra si el clínico lo aceptó tal cual o lo editó.
6. Desde el detalle de una herida existente, abrir **Seguimiento** para ver la gráfica de tendencia de área y el checkpoint Sheehan. Usar **Registrar seguimiento** (botón en el AppBar) para capturar una nueva visita subsecuente — al guardarla, la gráfica, el checkpoint y la foto "actual" se actualizan automáticamente con el dato recién creado.
7. Desde el detalle de un paciente, tocar cualquier ítem del **historial de consultas** para ver el detalle completo (solo lectura) de esa visita: mediciones, evaluación, recomendación Kura+, tratamiento y fotos.
8. `/reports` permite seleccionar pacientes y generar un PDF de reporte.
9. `/admin` (solo visible para el usuario admin) permite gestionar personal, sitios, el catálogo de la nota de seguimiento (alta manual, o descarga/carga de CSV en bloque — ver sección 3.4b) y activar premium por usuario.
10. `/import-export` permite previsualizar una importación CSV con mapeo de columnas y exportar mediciones a CSV.

---

## 7. Despliegue actual

- **Tipo**: demo estática (Flutter Web build) servida en el sandbox de desarrollo vía PM2 + `python3 -m http.server`.
- **Build**: `flutter build web --release` (exitoso).
- **Proceso**: PM2 `kuratracker-web`, puerto 3000 (`ecosystem.config.cjs`).
- **Nota de despliegue permanente**: esta demo corre en el sandbox de desarrollo, no en un dominio de producción de Cloudflare Pages ni en Supabase real. Para un despliegue permanente hay que: (a) decidir el hosting final del build web (Cloudflare Pages es viable ya que es un sitio estático), y (b) completar la conexión a Supabase real (sección 9) antes de considerar el sistema listo para datos reales de pacientes.

---

## 8. Funcionalidades NO implementadas todavía

1. **Motor Kura+ como Edge Function (Supabase, TypeScript)** — hoy el motor corre embebido en el cliente Dart; no existe todavía una versión servidor que sea la fuente de verdad para el cálculo "oficial" (ver decisión de arquitectura en sección 9).
2. **Bitácora de auditoría completa** — el trigger `audit_trigger_fn()` cubre `patients`, `wounds`, `consultations`, `wound_measurements`, `treatment_plans`, `kura_recommendations`, `staff`, `profiles`, y solo en INSERT/UPDATE/DELETE; `wound_assessments`/`wound_photos` no están en su alcance por diseño actual.
3. **Checkpoint de Sheehan — dos de los cuatro flags de penalización siguen sin regla definida**: `bajaAdherencia` (definitivo, cableado desde `wound_assessments.low_adherence`) e `infeccionActiva` (proxy INTERINO: cualquier criterio IWII marcado) ya alimentan el cálculo real (ver sección 3.4). `deterioroDelLecho` y `aumentoDeExudado` requieren una regla comparativa visita-actual-vs-visita-anterior que aún no se ha definido con el equipo clínico — se dejan en `false` a propósito, no se inventó la regla.
4. **Import CSV con persistencia real de `import_batches`** — la pantalla de import/export es funcional como demo de mapeo de columnas, pero no persiste el lote de importación como una fila real de la tabla `import_batches`.
5. **Autenticación real** (verificación de contraseña, recuperación de cuenta, expiración de sesión) — el login demo acepta cualquier contraseña.
6. **Prioridades 2–7 de la alineación con protocolos clínicos Kura+** (Prioridad 1 ya completada, ver secciones 1/5):
   - **P2** — número de fotos y modo de medición (2D/3D/manual) según tipo de visita (valoración=3, seguimiento=2, cierre=1); import/export eKare a preservar.
   - **P3** — confirmar con el equipo clínico que `ConsultationDetailScreen` (ya construida) satisface el detalle de consulta solo-lectura requerido.
   - **P4** — consentimientos (privacidad/fotográfico/desbridamiento) como registro en el expediente; bloqueo de captura de fotos sin consentimiento fotográfico.
   - **P5** — registro/formato de interconsultas-referencias (especialidad + motivo, ligado a la consulta).
   - **P6** — módulo de eventos adversos (clasificación, acciones, seguimiento pautado por severidad).
   - **P7** — catálogo "Terapia seca / Yodopovidona 10%" + tracking de desbridamiento (método/consentimiento/EVA/sangrado/respuesta).

---

## 9. Roadmap recomendado (próximos pasos)

El usuario del proyecto definió el criterio de priorización: **si el destino es un piloto clínico real (no solo demo), lo no negociable es conectar Supabase real (persistencia, multiusuario, RLS) y storage real de fotos** — ambos ya resueltos; el resto puede esperar.

**Orden de trabajo acordado:**

0. **⚠️ Aplicar la migración `0011_organizations.sql` al proyecto Supabase real** (paso manual pendiente, prioridad alta por incluir la corrección crítica de aislamiento de pacientes):
   - Revisar el contenido de `supabase/migrations/0011_organizations.sql` (organizations + organization_id en sites/profiles/staff/note_option_catalog/patients + backfill a "Kura+" + `current_organization_id()` + RLS reescrita de `patients`/`sites`/`staff`/`note_option_catalog`/`organizations`).
   - Aplicarla con `supabase db push` (o pegándola en el SQL Editor del proyecto) — es idempotente respecto al resto del esquema, no modifica las 9 tablas descendientes de `patients`.
   - Verificar tras aplicar: un admin de la organización "Kura+" solo debe ver pacientes con `organization_id` = Kura+; si en el futuro se crea una segunda organización, sus admins no deben ver pacientes de Kura+ ni viceversa.
1. **Conectar un proyecto Supabase real** — 📖 runbook detallado en [`SUPABASE_SETUP.md`](./SUPABASE_SETUP.md)
   - Provisionar proyecto (dueño: el cliente/usuario final, nunca esta cuenta de desarrollo), aplicar las migraciones SQL existentes (`supabase/migrations/`) **en orden estricto 0001→0011** (cada una depende de objetos creados por la anterior).
   - **Las 10 migraciones (`0001`→`0010`) están aplicadas y confirmadas contra el proyecto Supabase real del cliente**, incluyendo `0007_wound_assessment_adherence.sql` (columna `low_adherence`), `0008_follow_up_protocol_fields.sql` (protocolo de seguimiento), `0009_visit_type_cierre.sql` (enum `visit_type='cierre'`) y `0010_note_option_catalog.sql` (catálogo de conceptos de nota configurable por admin). **`0011_organizations.sql` está lista pero pendiente de aplicar** (ver paso 0 arriba).
   - Arquitectura de cliente **ya implementada** (`lib/services/remote/data_store.dart` + `supabase_data_store.dart` + `supabase_bootstrap.dart`): abstrae el origen de datos vía un `DataStore`; usa Supabase real cuando `AppConfig.isSupabaseConfigured` es `true` (URL + anon key inyectadas por `--dart-define`), y cae a `LocalStore` (modo demo local) cuando no hay credenciales — así el modo offline/demo sigue funcionando sin backend.
   - Verificar RLS en vivo **antes** de conectar la app (ver sección 4 de `SUPABASE_SETUP.md`): login autenticado + lectura de `/rest/v1/patients` confirmando que un clínico sin asignaciones no ve pacientes de otros.
   - Seed de datos sintéticos para el piloto: `supabase/seed/seed_synthetic_patients.sql` — 6 pacientes ficticios (2×escenario A, 2×B, 2×C; 5 etiologías distintas), idempotente, se corre desde el SQL Editor **después** de aplicar las migraciones y de verificar RLS.
2. **Storage real de fotos** — ✅ resuelto: `PhotoUploadService` sube al bucket `wound-evidence` y resuelve URLs firmadas.
3. **Migrar el motor Kura+ a una Supabase Edge Function (TypeScript)**
   - Puerto exacto de `kura_prognosis_model.dart`, `kura_clinical_adjustments.dart`, `kura_treatment_rules_engine.dart` y `kura_sheehan_checkpoint.dart` a TypeScript, usando los mismos JSON versionados de `assets/engine/`.
   - El cliente Flutter pasa a **consumir la Edge Function** como fuente de verdad para toda recomendación que se persiste en el expediente (auditable, versión de servidor).
   - El motor **Dart se conserva** exclusivamente para pronóstico en vivo mientras se captura y para el modo offline en campo (sin conexión) — nunca como fuente de verdad para lo que queda guardado en el expediente cuando hay conexión.
   - Requiere pruebas de paridad Edge Function (TS) ↔ Dart, con la misma tolerancia numérica ya validada Python↔Dart.
4. **Bitácora de auditoría completa**
   - Extender `logAudit()` (o el trigger `audit_trigger_fn()` ya en SQL) a updates y deletes de todas las entidades clínicas, no solo creaciones.
5. Pendientes menores: persistencia real de `import_batches`, autenticación con verificación real de contraseña.

---

## 10. Cómo correr el proyecto localmente

```bash
# Instalar dependencias
flutter pub get

# Ejecutar pruebas del motor (deben pasar 42/42)
flutter test test/engine/

# Ejecutar toda la suite
flutter test

# Analizar código (debe salir limpio de errores)
flutter analyze --no-fatal-infos --no-fatal-warnings
```

### ⚠️ Build-gate de verificación vs. build de producción — NUNCA usar `flutter build web --release` a secas

Este repo sirve **dos builds distintos** desde `build/` vía PM2 (ver `ecosystem.config.cjs`):

| Directorio | PM2 app | Puerto | Contenido |
|---|---|---|---|
| `build/web` | `kuratracker-web` | 3000 | **Producción** — compilado CON `--dart-define=SUPABASE_URL/ANON_KEY` reales |
| `build/web-demo` | `kuratracker-web-demo` | 3001 | **Demo** — compilado SIN esas credenciales (modo local/sintético) |

`flutter build web --release` sin `-o` sobrescribe **siempre** `build/web` por default. Correrlo como mero chequeo de "¿compila?" (sin las credenciales reales) **rompe producción silenciosamente** (la deja en modo demo) — esto ya pasó una vez en este proyecto.

**Por eso, para verificar que el build compila (paso de un build-gate, antes de pedir merge), usar siempre:**
```bash
./scripts/build_gate.sh
```
Este script compila a `build/web-gate/` (desechable, ignorado por git) y **nunca** toca `build/web` ni `build/web-demo`. También corre `flutter analyze` y `flutter test` antes del build.

**Para reconstruir producción de verdad** (después de cambios que deban llegar a `build/web`):
```bash
export SUPABASE_URL="https://<project-ref>.supabase.co"
export SUPABASE_ANON_KEY="<anon-key>"
./scripts/build_prod.sh
```
Este script compila con `--dart-define`, verifica con `grep` que el bundle contiene la URL real y NO el fingerprint de modo demo, reinicia `pm2 kuratracker-web` y confirma con `curl`.

```bash
# Servir los builds (PM2, ver ecosystem.config.cjs)
pm2 start ecosystem.config.cjs
curl http://localhost:3000/   # producción
curl http://localhost:3001/   # demo
```

Para aplicar el esquema SQL a un proyecto Supabase real (cuando esté provisionado):

```bash
supabase link --project-ref <project-ref>
supabase db push   # aplica supabase/migrations/*.sql en orden
```

---

## 11. Estructura del repositorio

```
lib/
  core/            # tema, config, providers de sesión, router, shell de navegación
  engine/          # motor Protocolo Kura+ (puro Dart, sin dependencias de Flutter)
    models/        # enums, KuraEngineInput, KuraEngineOutput
    rules/         # motor de reglas de tratamiento
  models/          # modelos de dominio (Site, Staff, Patient, Consultation, Wound, TreatmentPlan, AppUser)
  services/
    local_db/      # LocalStore (SharedPreferences) + DemoSeed
    remote/        # DataStore, SupabaseDataStore (Postgrest real)
    data_repository.dart      # API central de datos consumida por toda la UI
    photo_upload_service.dart # subida a Supabase Storage / fallback data-URL en modo demo
  features/        # una carpeta por módulo de UI (auth, dashboard, patients, consultation,
                   # wound_capture, treatment, follow_up, reports, admin, import_export)
assets/
  engine/          # kura_model_v2.json, kura_clinical_adjustments.json (versionados)
test/
  engine/          # 42 tests: paridad, casos límite, reglas de seguridad, Sheehan
supabase/
  migrations/      # 11 migraciones SQL (esquema, triggers, RLS, storage, WIFI/Braden/HbA1c,
                   # hardening RLS profiles, low_adherence, alineacion protocolo seguimiento,
                   # enum visit_type='cierre', catalogo de conceptos de nota,
                   # modelo Centro->Sitios->Personal + aislamiento critico de pacientes) —
                   # 0001-0010 aplicadas y confirmadas contra producción;
                   # 0011 lista y versionada, PENDIENTE de aplicar (ver seccion 9, paso 0)
  functions/kura-protocol-engine/  # carpeta reservada para la Edge Function TS (pendiente)
```

---

*Última actualización: Agregado cálculo de volumen editable por fórmula de Kundin (`volume_cm3 = Largo × Ancho × Profundidad × 0.327`) en ambas pantallas de captura (valoración y seguimiento), con detección/anotación de ajuste manual ("✎ Volumen ajustado manualmente") derivada por tolerancia (no un toggle persistido) en captura, detalle de consulta y tooltip de gráfica; migración additiva `0015_wound_measurements_volume_manual.sql` (columna `volume_manual`, pendiente de aplicación manual por Carlos); dos gráficas nuevas y additivas en el tablero de seguimiento (volumen en el tiempo con placeholder para heridas sin datos 3D, y composición del tejido en el tiempo) sin modificar la gráfica de área existente. 15 tests nuevos (`test/unit/wound_volume_test.dart`), suite completa 150/150, `flutter analyze` limpio de errores, `build_gate.sh` verde. No cambia lógica del motor de reglas (`rulesVersion` sin bump). Todo el trabajo vive en la rama `feat/volume-kundin-charts`, no en `main`, pendiente del visto bueno explícito del usuario para el merge — ver sección 3.4f.*

*Actualización previa: Agregado el rol `master` (administrador de plataforma) — migración `0012_master_role.sql` (versionada, pendiente de aplicación manual), `PlatformHomeScreen` con selector de centro reutilizando `StaffTab`/`SitesTab`/`NoteCatalogTab`, ruta `/platform` y nav exclusiva. 67/67 tests pasando (6 nuevos), `flutter build web --release` exitoso, verificado en vivo con Playwright (incluye un bug real de `RangeError` en avatar de personal sin folio, encontrado y corregido durante esta verificación). Todo el trabajo vive en la rama `feat/master-role`, no en `main`, hasta confirmación del usuario — ver sección 5.4. Pendiente: prueba negativa de privacidad contra Supabase real (requiere que se apliquen las migraciones 0011/0012 primero) y el bootstrap manual del primer master.*

*Actualización previa: Agregado el borrado de conceptos del catálogo de la nota de seguimiento (Administración → Configuración), junto al switch de activar/desactivar existente — `DataRepository.deleteNoteOption()` (delega en `deleteRow`, permitido por la RLS `note_option_catalog_admin_delete` de la migración 0011) + ícono `Icons.delete_outline` en cada fila con diálogo de confirmación ("¿Borrar este concepto? No afecta las notas ya guardadas."). El diálogo de confirmación usa explícitamente el patrón correcto de la sección 3.4d (`builder: (dialogCtx) => ...` / `Navigator.pop(dialogCtx, ...)`) para no reintroducir el bug de la pantalla en blanco. Se verificó con un test de integración que borrar un concepto del catálogo NO afecta las notas de seguimiento ya guardadas que usaron su texto (no hay FK, se guarda el label como texto plano) ni a los demás conceptos del mismo campo o de otros campos — 3 tests nuevos, 61/61 en la suite completa. Verificado también con reproducción en vivo (Playwright contra este sandbox): ícono visible en cada fila, diálogo con el texto exacto esperado, "Cancelar" no borra nada, "Borrar" elimina el concepto de la lista, y el `<canvas>` de CanvasKit se mantiene presente en todo momento (sin pantalla en blanco). Ver sección 3.4e.

*Actualización previa: Causa raíz REAL de "pantalla en blanco al crear concepto de catálogo" encontrada y corregida, con reproducción en vivo (Playwright contra sandbox de desarrollo, no contra Supabase real). Hallazgo clave: la pantalla en blanco ocurría también al pulsar "Cancelar" (sin tocar backend), lo que descartó el fix anterior (`fromJsonOrNull`, sección 3.4c) como causa de este síntoma específico — ese fix sigue siendo válido para su propio mecanismo (fila cacheada malformada), pero no era la causa de este bug. Causa real: la app usa `ShellRoute` (navegador anidado) y varios diálogos hacían `Navigator.pop(context)` con el `context` EXTERNO (el de la pantalla que abrió el diálogo) en vez del `context` propio del `builder` del diálogo, provocando que el `pop` cerrara la ruta de fondo en vez del diálogo — sin lanzar ninguna excepción de Dart, por lo que no había stack trace ni SnackBar ni activación de `ErrorWidget.builder`, y el `<canvas>` de CanvasKit desaparecía del DOM sin recuperación. Fix: nombrar el `context` del `builder` (`dialogCtx`) y usarlo en todos los `Navigator.pop` de ese diálogo, en `admin_home_screen.dart` (diálogo de resumen de importación y `_promptForLabel`) e `import_export_screen.dart` (diálogo de exportación CSV) — ver sección 3.4d. Verificado: `flutter analyze` (0 errores), `flutter test` (58/58), y reproducción en vivo post-fix confirmando que ni "Cancelar" ni "Guardar" producen ya pantalla en blanco, y que el concepto nuevo aparece correctamente en la lista tras "Guardar". Nota de alcance: verificado en este sandbox de desarrollo (demo local); se recomienda que el cliente confirme también contra su Supabase/Cloudflare Pages de producción real, dado que nunca se ha probado directamente contra ese entorno en esta conversación.*
