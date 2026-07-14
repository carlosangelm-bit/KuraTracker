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
| Esquema Supabase (SQL: tablas, RLS, triggers, storage) | ✅ Diseñado, versionado en `supabase/migrations/` **y aplicado** (0001→0007, incl. `low_adherence`) al proyecto Supabase real del cliente; admin creado y promovido |
| Persistencia real / multiusuario / RLS en vivo | ✅ Migraciones aplicadas y **smoke-test end-to-end completado contra Supabase real** (login → paciente → captura → tratamiento con sugerencia Kura+ → seguimiento con checkpoint Sheehan → datos listos para reporte), incl. bug de `search_path` corregido y validado en producción; verificación formal de RLS con prueba negativa (segundo usuario clínico sin asignaciones) sigue diferida hasta antes de cargar datos reales, por decisión del cliente — se avanza con datos sintéticos |
| Registro de seguimiento (visitas subsecuentes) | ✅ Completo — formulario "Registrar seguimiento" persiste medición + evaluación + foto en Supabase (`visit_type='seguimiento'`); tablero de seguimiento 100% derivado de la serie real, sin datos de ejemplo (ver sección 3.4) |
| Detalle de consulta (solo lectura) desde el historial | ✅ Completo — historial de consultas del paciente es tappable y navega a `ConsultationDetailScreen` (ver sección 3.5) |
| Storage real de fotos (bucket `wound-evidence`) | ✅ Implementado — `PhotoUploadService` sube a Supabase Storage con ruta `{wound_id}/{consultation_id}/...` y resuelve URL firmada; cae a data-URL base64 automáticamente en modo demo sin credenciales |
| Motor como Edge Function (Supabase, TypeScript) | ❌ Pendiente — hoy el motor corre embebido en el cliente Dart |
| Bitácora de auditoría | ⚠️ Parcial — cubre creación de paciente/medición/plan de tratamiento vía trigger SQL; faltan updates/deletes. `wound_assessments`/`wound_photos` no están en la lista de tablas auditadas (por diseño del trigger existente) |
| Import/Export CSV (eKare) | ✅ Demo funcional (mapeo configurable en UI); persistencia real de `import_batches` pendiente |
| Generación de PDF (reportes) | ✅ Funcional en cliente vía `pdf`/`printing` |

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

### 3.5 Detalle de consulta (solo lectura)
`lib/features/consultation/consultation_detail_screen.dart`. Cada ítem del historial de consultas en `patient_detail_screen.dart` es tappable y navega a esta pantalla, que muestra —solo lectura, respetando RLS— todo lo registrado en esa consulta: datos generales (fecha, tipo de visita, sitio, personal sanitario), la(s) herida(s) evaluada(s) en la consulta y su evaluación (mediciones, composición del lecho, exudado, infección, borde, piel perilesional), la recomendación Kura+ emitida si la hubo (escenario A/B/C, fenotipo comercial, régimen, interconsultas), el tratamiento aplicado y las fotos tomadas en esa visita. Como `wounds` no tiene FK directa a `consultations`, la asociación herida↔consulta se infiere del lado del cliente revisando qué mediciones/evaluaciones de cada herida tienen ese `consultation_id`. El **tipo de exudado** (`exudate_type`) ahora se lee y muestra correctamente aquí — `WoundAssessment.fromJson()`/`toJson()` lo parsean y persisten (antes se perdía en el round-trip y siempre aparecía vacío).

### 3.6 Reportes
`lib/features/reports/reports_screen.dart`: selección múltiple de pacientes, filtros (consultas/seguimientos/antecedentes/evidencias — todas o primera/última), botón de generación de PDF.

### 3.6 Roles y administración
- **Administrador**: gestiona personal (alta con folio automático), sitios, pacientes, y activa función premium por usuario.
- **Personal sanitario/clínico**: solo ve pacientes que le fueron asignados (`staff_patient_assignments`).
- Pantalla `lib/features/admin/admin_home_screen.dart` con pestañas Usuarios / Personal / Sitios.

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
| `/import-export` | Import/Export CSV | Interoperabilidad eKare |

---

## 5. Modelo de datos y almacenamiento

### 5.1 Esquema objetivo (Supabase / Postgres) — diseñado, no desplegado aún
`supabase/migrations/`:
- `0001_core_schema.sql` — 17 tablas: `profiles`, `sites`, `staff`, `staff_patient_assignments`, `patients`, `patient_comorbidities`, `consultations`, `wounds`, `wound_assessments`, `wound_measurements`, `perfusion_nutrition_data`, `wound_photos`, `treatment_plans`, `treatment_components`, `kura_recommendations`, `sheehan_checkpoints`, `audit_log`, `import_batches`. Incluye tipos `enum`, constraints `CHECK` (suma de composición del lecho ≤ 100.01) e índices.
- `0002_triggers_and_functions.sql` — folios automáticos, `updated_at`, `audit_trigger_fn()` (SECURITY DEFINER, AFTER INSERT/UPDATE/DELETE en tablas clínicas), `handle_new_auth_user()`, helpers `is_admin()`, `current_staff_id()`, `current_user_role()`.
- `0003_row_level_security.sql` — RLS en todas las tablas clínicas: acceso total para admin, y para personal clínico solo si existe una fila en `staff_patient_assignments` para ese paciente.
- `0004_storage_buckets.sql` — bucket `wound-evidence` (límite 17 825 792 bytes = 17 MB), políticas RLS sobre `storage.objects` basadas en el primer segmento de la ruta (`(storage.foldername(name))[1] = wound_id`).
- `0005_wifi_braden_hba1c.sql` — columnas `braden_score`/`hba1c_pct` en `wound_assessments`.
- `0006_prevent_profile_privilege_escalation.sql` — hardening de RLS en `profiles`.
- `0007_wound_assessment_adherence.sql` — columna `low_adherence boolean not null default false` en `wound_assessments`, para el flag de baja adherencia capturado en el formulario de seguimiento. **Aplicada y verificada contra el proyecto Supabase real del cliente** — `wound_assessments.low_adherence` ya existe en producción y el checkpoint de Sheehan ya la consume (ver sección 3.4).

### 5.2 Almacenamiento actual (modo demo local-first)
`lib/services/local_db/local_store.dart`: `SharedPreferences` usado como almacén de documentos JSON; `Collections` define nombres de colección que son espejo exacto de las tablas SQL anteriores. `demo_seed.dart` siembra automáticamente, en el primer arranque:
- 3 sitios, 3 perfiles (1 admin + 2 clínicos), 2 personal sanitario.
- 5 pacientes cubriendo las 4 etiologías + un caso de **isquemia crítica** (ABI 0.38) usado como caso de prueba de la regla de seguridad "no desbridar".
- Comorbilidades, heridas, consultas (incluye seguimientos para graficar tendencia), evaluaciones, mediciones seriadas, datos de perfusión/nutrición y un plan de tratamiento de ejemplo.

**Importante**: hoy no hay sincronización real entre dispositivos ni multiusuario concurrente — cada instancia del navegador/app tiene su propio almacén local. Esto es intencional para la fase de demo, y es el primer punto del roadmap hacia piloto (sección 9).

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
9. `/admin` (solo visible para el usuario admin) permite gestionar personal, sitios y activar premium por usuario.
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

---

## 9. Roadmap recomendado (próximos pasos)

El usuario del proyecto definió el criterio de priorización: **si el destino es un piloto clínico real (no solo demo), lo no negociable es conectar Supabase real (persistencia, multiusuario, RLS) y storage real de fotos** — ambos ya resueltos; el resto puede esperar.

**Orden de trabajo acordado:**

1. **Conectar un proyecto Supabase real** — 📖 runbook detallado en [`SUPABASE_SETUP.md`](./SUPABASE_SETUP.md)
   - Provisionar proyecto (dueño: el cliente/usuario final, nunca esta cuenta de desarrollo), aplicar las 7 migraciones SQL existentes (`supabase/migrations/`) **en orden estricto 0001→0007** (cada una depende de objetos creados por la anterior: 0002 de las tablas de 0001; 0003/0004 de las funciones helper de 0002; 0005/0006/0007 son alteraciones incrementales sobre el esquema base).
   - **Las 7 migraciones (`0001`→`0007`) están aplicadas y verificadas contra el proyecto Supabase real del cliente**, incluyendo `0007_wound_assessment_adherence.sql` (columna `low_adherence`).
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

# Analizar código (debe salir limpio de errores)
flutter analyze --no-fatal-infos --no-fatal-warnings

# Compilar build web de producción
flutter build web --release

# Servir el build (ejemplo con PM2, ver ecosystem.config.cjs)
pm2 start ecosystem.config.cjs
curl http://localhost:3000/
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
  migrations/      # 7 migraciones SQL (esquema, triggers, RLS, storage, WIFI/Braden/HbA1c,
                   # hardening RLS profiles, low_adherence) — las 7 (0001–0007) aplicadas y
                   # verificadas contra el proyecto Supabase real del cliente
  functions/kura-protocol-engine/  # carpeta reservada para la Edge Function TS (pendiente)
```

---

*Última actualización: cableado de los flags de penalización del checkpoint de Sheehan (`bajaAdherencia` definitivo desde `wound_assessments.low_adherence`, `infeccionActiva` proxy interino desde criterios IWII) con visibilidad del % ajustado y las penalizaciones aplicadas en el tablero de seguimiento; parseo de `exudate_type` en `WoundAssessment` (round-trip completo toJson↔fromJson). Migraciones 0001–0007 confirmadas aplicadas en el Supabase real del cliente. Build/analyze/tests verificados, demo desplegada en sandbox de desarrollo.*
