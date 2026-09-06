# KuraTracker — contexto del proyecto

Expediente clínico electrónico (EHR) para el cuidado de heridas crónicas.
**Flutter Web** (Dart ^3.6.0, Riverpod, go_router con ShellRoute) + **Supabase**
(Postgres + Auth + RLS + Storage). Producción compila desde `main`.

> Este archivo lo carga Claude Code automáticamente al abrir el proyecto. Sirve
> como fuente única de contexto entre máquinas (viaja con Git; no requiere copiar
> nada aparte). **No contiene secretos** — esos viven en GitHub Actions y Supabase.

---

## Trabajar en otra máquina

1. `git clone https://github.com/carlosangelm-bit/KuraTracker.git`
2. Instalar el toolchain (abajo). No hace falta OneDrive ni copiar archivos: GitHub
   es la fuente de verdad del código y este `CLAUDE.md` trae el contexto.
3. Flujo normal de Git: `git pull` al empezar, `git push` al terminar.

Lo que **no** viaja con el clone y hay que tener en la máquina nueva:
- **Flutter** y **Supabase CLI** (toolchain).
- **Secrets**: no están en el repo; el CI de GitHub y Supabase ya los tienen, así
  que el deploy funciona desde cualquier máquina sin copiar nada.

---

## Toolchain y desarrollo local

- **Flutter para CI = 3.27.1** (lo fija `.github/workflows/deploy.yml`). El build de
  producción usa esa versión; escribe código compatible con ella (p. ej.
  `DropdownButtonFormField` usa `value:`, no `initialValue:`; `Color.withValues(alpha:)`
  existe desde 3.27).
- **La versión local de Flutter puede diferir** (aquí ~3.44) y **no compila la UI de
  forma confiable**. Validar con `flutter analyze` (objetivo: **0 errores**), **no** con
  `flutter build`/`flutter test`.
- **`pubspec.lock`**: revertir cualquier cambio local antes de commitear
  (`git checkout -- pubspec.lock`) — el lock lo resuelve el CI con su toolchain.

## Deploy (CI/CD propio)

- **Desplegar = fusionar a `main` y hacer push.** GitHub Actions
  (`.github/workflows/deploy.yml`) hace todo en cada push a `main`:
  1. `migrations`: `supabase db push` (aplica migraciones nuevas).
  2. `build_deploy` (depende de migrations): compila con Flutter 3.27.1 y publica en
     **Cloudflare Pages** — **prod** (con dart-defines de Supabase) y **demo** (sin
     credenciales, usa `LocalStore`).
  3. `deploy_functions`: despliega una lista ACOTADA de funciones con `--use-api`
     (admin-create-user, acuity-proxy, mercadopago-webhook/-sync-charge/-point-intent,
     stripe-create-checkout/-webhook, vac-bot, support-bot, shopify-sync-catalog/-inventory,
     demo-lead).
     Los webhooks/endpoints que deben quedar con la URL abierta (stripe-webhook,
     mercadopago-webhook, demo-lead) se despliegan con `--no-verify-jwt` para no
     re-habilitar `verify_jwt`. `demo-lead` es la portera de leads de la demo →
     Bitrix (`crm.item.add`, entityTypeId=1). Secrets en Supabase: `BITRIX_WEBHOOK_URL`,
     `BITRIX_ASSIGNED_BY_ID` (responsable comercial, OPCIONAL: sin él los leads caen
     en la cuenta del webhook), `BITRIX_USERTYPE_FIELD` (campo de lista del tipo de
     usuario = `ufCrm_LEAD_1788382308670`; la etiqueta se traduce al ID de su opción
     vía `crm.item.fields`), `BITRIX_SOURCE_ID` (OPCIONAL, override del ORIGEN; por
     defecto `UC_HRFW6S` = origen propio "Demo KuraTracker" del portal — sin fijarlo
     Bitrix pone "Llamada" por omisión). El EVENTO no usa campo propio (decisión de Carlos): se
     concatena a `sourceDescription` como "Demo KuraTracker · <evento>". El build de la
     demo recibe el dart-define `LEADS_ENDPOINT` (URL de la función), `AVISO_URL` (aviso
     de privacidad, `vars.AVISO_URL`) y `DEMO_EVENT` (evento, `vars.DEMO_EVENT`).
- Los secrets de Cloudflare se llaman **`CLOUDFARE_API_TOKEN` / `CLOUDFARE_ACCOUNT_ID`**
  (sin la "L", intencional). El token Cloudflare requiere permiso *Account · Cloudflare
  Pages · Edit*.
- Hosting: **app.kuramas.com** (prod) y **demo.kuramas.com** (demo) en Cloudflare Pages;
  DNS en Google Cloud DNS (**no tocar DNS**). `tracker.kuramas.com` = Custom Domain de
  Supabase.
- **Sandbox (staging)**: la rama **`staging`** corre el MISMO `deploy.yml` con el
  environment de GitHub `staging` → proyecto Supabase propio + Cloudflare Pages
  `kuratracker-sandbox` (`kuratracker-sandbox.pages.dev`), app con `APP_ENV=sandbox`
  (franja naranja SANDBOX), sin demo. Datos sintéticos: workflow manual "Sandbox ·
  seed de datos" (`seed_sandbox.sql` + `seed_synthetic_patients.sql`; 7 cuentas
  `*@sandbox.kuratracker.mx`, 3 centros `is_test`). Flujo: feature → `staging` →
  probar → `main`. Runbook: `SANDBOX_SETUP.md`. Nunca datos reales en el sandbox.

## Convenciones

- **Ramas por feature/fix**; merge `--no-ff` a `main`. Entregas grandes = por fases
  (cada fase = 1 deploy).
- **Mensajes de commit** terminan con el trailer `Co-Authored-By: Claude ...`.
- **Permisos por rol**: usa SIEMPRE los getters del conjunto de roles
  (`user.isAdmin`, `user.isMaster`, `user.canDiagnose`, `user.isNurse`), NUNCA
  `user.role == AppRole.x`. El rol escalar es un espejo del conjunto; comparar
  contra él vuelve a acoplar al modelo viejo y se rompe con roles combinados.
- **Orden de triggers.** Postgres dispara los `BEFORE` en orden alfabético por nombre de
  trigger. Un candado llamado `trg_prevent_*` corre **antes** que una derivación llamada
  `trg_sync_*`, así que valida la entrada cruda y no el estado final. Los triggers de
  validación se nombran `trg_zz_*` para que corran al final, y comparan **todas** las columnas
  que representan el mismo dato (p. ej. `role` y `roles`).
- **Demo seed (`_seedFlag`).** Todo cambio al CONTENIDO de `demo_seed.dart` exige subir
  `_seedFlag` (`seeded_vN` → `vN+1`). `ensureSeeded` no re-siembra si el flag ya está puesto,
  así que cambiar el código del seed sin subir el flag **no tiene efecto en ningún navegador
  que ya sembró** (el dato viejo se queda). Es la contraparte, en la capa de datos, del caché
  del service worker en la capa de código. El aislamiento/lógica es código (se despliega solo);
  lo sembrado es dato (exige el flag).
- **Migraciones** en `supabase/migrations/NNNN_*.sql`, numeradas en secuencia. La RLS se
  extiende de forma **ADITIVA** (nuevas policies `SELECT`/`INSERT` que se OR-ean con las
  existentes; nunca reescribir/borrar policies vigentes). Helpers `SECURITY DEFINER` para
  chequeos de rol/pertenencia. Gotcha Postgres: un valor de enum nuevo (`alter type add
  value`) va **solo** en su propia migración/transacción y no puede usarse como literal en
  la misma tx → comparar por `::text`.
- **Capa de datos**: abstracción `DataStore` con dos implementaciones —
  `LocalStore` (demo, SharedPreferences, con flag `seeded_vN` en el seed) y
  `SupabaseDataStore` (prod, Postgrest + RLS). `insertRow` hace `.select().single()` →
  lanza si RLS bloquea (0 filas); usar RPC cuando la RLS no permita el UPDATE/INSERT directo.

## Backend Supabase

- Proyecto prod ref: `mhnhgnzajdjhllypdutr` (URL `https://mhnhgnzajdjhllypdutr.supabase.co`;
  la anon key es pública en el cliente, pero **nunca** se commitea — va por dart-define/secret).
- Roles (`user_role`): `admin`, `clinico`, `master`, `cuidador`, `enfermeria`. Espejo en
  la app: `AppRole` (`lib/models/app_user.dart`) con `isMaster`/`isNurse`/`canDiagnose`.
- Integración **Acuity** por Basic Auth (agenda de citas); Edge Functions para
  webhook/backfill/fotos, acotadas a staff activo mapeado por email. Fotos de herida en
  bucket privado (`acuity-intake`); **las URLs S3 dentro de `appointments.raw` caducan en
  1 h**.

## Estado actual (módulos)

- **Tipos de centro** (multi-centro): clínica de heridas (morado), hospital (azul),
  cuidadores (rosa). Membresías multi-centro con switcher (ícono de apósitos). Módulos
  configurables por el master a nivel centro/sitio/usuario.
- **Módulo de Prevención / Riesgo**: valoración de Braden, tablero de riesgo, agenda de
  **tareas** preventivas (autogeneradas desde reglas/cadencias, editables).
- **Prevención hospitalaria** (hospital, capa documental — no toca el motor de
  tratamiento): panel de tarjetas por banda de Braden, **rondas** (la pestaña de agenda en
  hospital enruta a `/prevention-agenda`, no a la agenda de citas), perfil con cumplimiento
  por tipo/global + bitácora de auditoría, y **dashboard del centro** (`/hospital`) con
  editor de turnos (`organizations.shift_config`). Migración base: `0046`.
- **Motor de visión de heridas** (`lib/engine/vision`, Dart puro, on-device): «Medir con
  foto» en valoración y seguimiento propone largo/ancho/composición del lecho desde una
  foto con tarjeta WoundCalibrate (AprilTags) o disco de referencia. `area_cm2` NO cambia
  (sigue L×A×0,785); el área real va en `area_planimetric_cm2`; origen en
  `measurement_source` + `vision_meta` (migración `0108`). Umbrales en
  `assets/engine/vision/*.json`. Ver `docs/engine/motor_vision.md`. **Pendiente**:
  `card_spec.json` real (hoy `is_placeholder`) y validación con fotos reales.
- **Rol enfermería** + hospital **centrado en el paciente** (cualquier staff activo ve a
  todos los pacientes del centro; las tareas siguen al paciente, sin dueño). **Cuidador**:
  login por teléfono+clave (correo sintético), acceso reducido a sus pacientes asignados.
- Detalle histórico y decisiones por feature: ver los archivos de memoria de Claude
  (fuera del repo, en `~/.claude/.../memory/`); este `CLAUDE.md` es el resumen durable.

## Pendientes / notas

- **Validación clínica pendiente** (María): reglas, cadencias, umbrales de Braden y la
  paleta azul del hospital siguen siendo **borrador**.
- **Incidencia/prevalencia de LPP**: pendiente de definición clínica (numerador/
  denominador/ventana); hay un espacio marcado en el dashboard.
- **SMTP no configurado** en Supabase → `admin-create-user` entrega contraseña temporal
  (no manda invitación).

## Seguridad (nunca commitear)

- Claves/tokens/contraseñas de cualquier tipo (anon key, service role, API keys de
  Acuity/Cloudflare, DB password). Van en GitHub Secrets / Supabase / dart-defines.
- No tocar DNS (Google Cloud DNS). El deploy de funciones se dirige a una lista
  acotada (ver `.github/workflows/deploy.yml`), no a todas.
