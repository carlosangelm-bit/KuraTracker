# SANDBOX_SETUP.md — Entorno de pruebas (staging) de KuraTracker

Runbook para levantar y operar el **sandbox**: una copia completa de la
plataforma (Supabase + app web + Edge Functions) separada de producción, con
datos 100 % sintéticos, donde se prueban funcionalidades nuevas antes de
fusionarlas a `main`.

> **Regla de oro:** nada de lo que pase en el sandbox toca `app.kuramas.com`
> ni el proyecto Supabase `mhnhgnzajdjhllypdutr`. El sandbox tiene su propio
> proyecto Supabase, su propio sitio en Cloudflare Pages y sus propios secrets.
> Ningún dato real de pacientes entra al sandbox — sólo el seed sintético.

---

## 0. Cómo queda armado

| | Producción | Sandbox |
|---|---|---|
| Rama de Git | `main` | `staging` |
| GitHub Environment | `production` | `staging` |
| Proyecto Supabase | `mhnhgnzajdjhllypdutr` | el que crees en el paso 1 |
| Cloudflare Pages | `kuratracker-prod` → app.kuramas.com | `kuratracker-sandbox` → `kuratracker-sandbox.pages.dev` |
| Demo (LocalStore) | `kuratracker-demo` → demo.kuramas.com | no se publica |
| Banner en la app | ninguno | franja naranja **SANDBOX** arriba |
| Datos | reales | `seed_sandbox.sql` + `seed_synthetic_patients.sql` |
| Edge Functions | credenciales reales | credenciales **de prueba** de cada proveedor |

**Un solo workflow** (`.github/workflows/deploy.yml`) sirve a ambos: un push a
`staging` corre exactamente los mismos jobs (checks → migraciones → build +
Pages → funciones) pero con los secrets del environment `staging`. Los nombres
de los secrets son idénticos en los dos environments; GitHub resuelve el valor
según el environment del job.

**Guardias anti-cruce.** Si en el environment `staging` falta un secret, GitHub
usa el secret de *repositorio* del mismo nombre —que hoy es el de producción—
sin avisar. Por eso el workflow aborta en staging si `SUPABASE_PROJECT_REF`,
`SUPABASE_URL` o `SUPABASE_DB_URL` contienen el ref de producción. Aun así,
completa **todos** los secrets del paso 3 antes del primer push.

Flujo de trabajo:

```
feature/xyz ──merge──▶ staging ──(CI: sandbox)──▶ pruebas en kuratracker-sandbox.pages.dev
                          │
                          └── cuando está bien ──merge──▶ main ──(CI: producción)
```

---

## 1. Proyecto Supabase del sandbox (una sola vez, ~10 min)

1. [supabase.com](https://supabase.com) → **New project** en la misma
   organización que el de producción. Nombre sugerido: `kuratracker-sandbox`.
   Misma región que producción. Guarda la contraseña de la BD en tu gestor de
   contraseñas.
2. Espera a que termine de aprovisionar. Anota:
   - **Project ref** (Project Settings → General), p. ej. `abcdefghijklmnopqrst`.
   - **URL**: `https://<ref>.supabase.co`.
   - **anon / publishable key** (Project Settings → API Keys).
   - **Cadena "Session pooler"** (Project Settings → Database → Connection
     string → pestaña *Session pooler*). Es la que funciona desde GitHub
     Actions (IPv4); la "Direct connection" es sólo IPv6 y falla en los
     runners. Sustituye `[YOUR-PASSWORD]` por la contraseña de la BD.
3. **Authentication → Providers → Email**: deja *Confirm email* **apagado**
   (igual que en producción: `admin-create-user` y el login de cuidador por
   teléfono dependen de ello). No configures SMTP.
4. **No apliques migraciones a mano.** Las 107 migraciones se aplican solas en
   el primer push a `staging` (`supabase db push` sobre un proyecto vacío).
   Se verificó que las 107 corren limpias, en orden, desde cero.

> Costo: un proyecto adicional en Supabase se cobra según el plan de la
> organización (los proyectos del plan gratuito son limitados y se pausan por
> inactividad; en plan Pro cada proyecto extra tiene costo mensual). Puedes
> **pausar** el proyecto sandbox cuando no se use y reanudarlo antes de una
> ronda de pruebas.

## 2. Proyecto de Cloudflare Pages (una sola vez, ~3 min)

1. Cloudflare → **Workers & Pages → Create → Pages → Upload assets** (Direct
   Upload). Nombre **exacto**: `kuratracker-sandbox`. Sube cualquier archivo
   vacío como primer deploy: el CI lo reemplaza en el primer push.
2. La URL queda como `https://kuratracker-sandbox.pages.dev`. **No** agregues
   dominio personalizado (eso tocaría el DNS de Google Cloud, que no se toca).
3. El token `CLOUDFARE_API_TOKEN` que ya usa producción sirve también aquí (es
   por cuenta, no por proyecto).

## 3. GitHub: environment `staging` y sus secrets (una sola vez, ~10 min)

Repo → **Settings → Environments → New environment** → `staging`.
Sin *Required reviewers* (el sandbox debe desplegar solo). En **Environment
secrets** agrega, con estos nombres exactos:

| Secret | Valor (del proyecto **sandbox**) |
|---|---|
| `SUPABASE_PROJECT_REF` | ref del paso 1 |
| `SUPABASE_DB_PASSWORD` | contraseña de la BD del sandbox |
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | anon / publishable key del sandbox |
| `SUPABASE_DB_URL` | cadena *Session pooler* completa (para el seed) |
| `SANDBOX_USER_PASSWORD` | contraseña que tendrán las 7 cuentas de prueba (≥ 8 caracteres) |
| `SHOPIFY_STOREFRONT_TOKEN` | token Storefront de la tienda de **desarrollo** de Shopify (o vacío) |

`SUPABASE_ACCESS_TOKEN` (tu Personal Access Token) y `CLOUDFARE_API_TOKEN` /
`CLOUDFARE_ACCOUNT_ID` son por cuenta: si ya están como secrets de repositorio,
staging los hereda y no hay que duplicarlos.

> **Higiene recomendada:** mueve los secrets de producción que hoy estén a
> nivel *repositorio* (`SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`,
> `SUPABASE_URL`, `SUPABASE_ANON_KEY`) al environment `production`. Así una
> rama nueva sin environment **no** hereda credenciales de producción.

Crea la rama:

```bash
git checkout main && git pull
git checkout -b staging
git push -u origin staging
```

Recomendado: **Settings → Branches → Add rule** para `staging` con "Require a
pull request before merging" apagado (para poder empujar directo) pero
"Do not allow bypassing" para `main` intacto como está hoy.

## 4. Primer despliegue

Cualquier push a `staging` dispara `deploy.yml` con el environment `staging`.
Para el primero basta con la rama recién creada (o un `workflow_dispatch`
seleccionando la rama `staging`). Verifica en Actions que:

1. `checks` pasa (analyze + tests).
2. `migrations` muestra el guardia `OK: staging apunta a <ref>` y aplica las
   107 migraciones (tarda 1–3 min).
3. `build_deploy` publica en `kuratracker-sandbox` (**no** hay pasos de demo).
4. `deploy_functions` despliega las 12 funciones al proyecto sandbox.

Abre `https://kuratracker-sandbox.pages.dev`: debe verse la **franja naranja
SANDBOX** arriba. Si no se ve, el build no llevó `APP_ENV=sandbox` (revisa el
job `build_deploy`).

## 5. Sembrar los datos de prueba

Actions → **"Sandbox · seed de datos"** → *Run workflow* → escribe `SANDBOX` en
el campo de confirmación. Tarda ~1 min y deja:

| Cuenta | Rol(es) | Centro |
|---|---|---|
| `master@sandbox.kuratracker.mx` | master | Kura+ (plataforma) |
| `admin@sandbox.kuratracker.mx` | admin | Clínica Sandbox |
| `clinico@sandbox.kuratracker.mx` | clinico (con cédula) | Clínica Sandbox |
| `independiente@sandbox.kuratracker.mx` | admin + clinico | Clínica Sandbox |
| `admin.hospital@sandbox.kuratracker.mx` | admin | Hospital Sandbox |
| `enfermeria@sandbox.kuratracker.mx` | enfermeria | Hospital Sandbox |
| teléfono **5550001234** | cuidador (login por teléfono + clave) | Cuidadores Sandbox |

Contraseña de todas: la que pusiste en `SANDBOX_USER_PASSWORD`.

Datos: los 6 pacientes clínicos validados contra el motor Protocolo Kura+
(2 A / 2 B / 2 C, asignados a la Dra. Clínica Sandbox), 3 internados en el
hospital con Braden 9 / 15 / 19 y tareas preventivas (una vencida, una de hoy,
una futura), 1 paciente domiciliario asignado al cuidador, consentimientos
otorgados y el catálogo de conceptos de nota copiado a los 3 centros. Los tres
centros llevan `organizations.is_test = true`.

**Para "resetear" el sandbox** después de una sesión de pruebas, vuelve a
correr el mismo workflow: borra sus propias filas y las re-siembra. Lo que los
usuarios hayan creado *fuera* de esas filas (pacientes nuevos, etc.) se queda;
si quieres una BD virgen, ver §8.

## 6. Edge Functions: credenciales de prueba de cada proveedor

Las funciones se despliegan al proyecto sandbox pero leen sus secrets de
**Supabase → Edge Functions → Secrets** de ese proyecto. Sin ellos, cada
función responde con error de configuración (no rompe la app). Configura sólo
las que vayas a probar, siempre con credenciales **sandbox/test** del
proveedor:

| Función | Secrets | De dónde |
|---|---|---|
| `mercadopago-*` | `MP_MODE=test`, `MP_ACCESS_TOKEN_TEST`, `MP_WEBHOOK_SECRET` | Mercado Pago → Tus integraciones → credenciales de **prueba** |
| `stripe-*` | `STRIPE_SECRET_KEY` (`sk_test_…`), `STRIPE_WEBHOOK_SECRET`, `APP_PUBLIC_URL=https://kuratracker-sandbox.pages.dev` | Stripe → modo **Test** → Developers |
| `shopify-*` | `SHOPIFY_STORE_DOMAIN`, `SHOPIFY_ADMIN_TOKEN`, `SHOPIFY_CLIENT_ID`, `SHOPIFY_CLIENT_SECRET`, `SHOPIFY_API_VERSION` | una **development store** de Shopify Partners, nunca la tienda real |
| `acuity-*` | `ACUITY_USER_ID`, `ACUITY_API_KEY` | Acuity no tiene modo sandbox: usa una cuenta de prueba separada o deja sin configurar |
| `demo-lead` | `BITRIX_WEBHOOK_URL`, … | **No configurar** en sandbox (mandaría leads falsos al CRM) |
| `vac-bot`, `support-bot` | `CUSTOMGPT_*` | pueden reutilizar los de producción (sólo lectura) |
| `admin-create-user` | ninguno extra | usa `SUPABASE_SERVICE_ROLE_KEY` que Supabase inyecta solo |

Los webhooks de Stripe / Mercado Pago de prueba deben apuntar a
`https://<ref-sandbox>.supabase.co/functions/v1/stripe-webhook` (o
`mercadopago-webhook`), registrados en el dashboard de **prueba** del proveedor.

## 7. Probar una funcionalidad (flujo diario)

```bash
# 1. Trabaja en tu rama de feature como siempre
git checkout -b feat/lo-que-sea
# … commits …

# 2. Llévala al sandbox
git checkout staging && git pull
git merge --no-ff feat/lo-que-sea
git push                      # → CI despliega al sandbox (3–6 min)

# 3. Prueba en https://kuratracker-sandbox.pages.dev con las cuentas del §5
#    (si la feature trae migraciones, ya están aplicadas al sandbox)

# 4. ¿Bien? Fusiona a main como hoy
git checkout main && git pull
git merge --no-ff feat/lo-que-sea
git push                      # → CI despliega a producción
```

Notas:

- **Migraciones**: se aplican al sandbox en el paso 2 con el mismo
  `supabase db push` que usa producción, así que un error de SQL sale en el
  sandbox y no en producción. Si una migración quedó mal y ya se aplicó al
  sandbox, corrígela en una migración **nueva** (nunca edites una ya aplicada) o
  resetea el sandbox (§8).
- **`staging` puede divergir de `main`** si acumula features que aún no se
  fusionan. Si se ensucia, es legítimo rehacerla:
  `git checkout staging && git reset --hard main && git push --force-with-lease`
  (sólo `staging`; **nunca** `main`).
- **Motor de visión (`feat/wound-vision-engine`)**: es el primer candidato.
  Al fusionarlo a `staging` podrás probar cámara + tarjeta de calibración con
  las 7 cuentas y fotos sintéticas, sin tocar expedientes reales.

## 8. Reset total del sandbox (BD virgen)

Cuando el esquema quedó inconsistente (migración fallida a medias, pruebas
destructivas) lo más limpio es recrear la BD desde las migraciones:

```bash
supabase link --project-ref <ref-sandbox>
supabase db reset --linked        # DESTRUYE la BD del sandbox y re-aplica supabase/migrations/
```

La CLI pide confirmar el ref; verifica **dos veces** que es el del sandbox.
Después corre otra vez el workflow de seed (§5) y re-despliega las funciones
(re-ejecuta `deploy.yml` en `staging` con *Run workflow*).

## 9. Qué NO hacer

- No copiar datos de producción al sandbox, ni "anonimizados a mano": los
  expedientes reales están sujetos a NOM-004 / NOM-024 y al aviso de privacidad.
- No configurar `demo-lead` / Bitrix en el sandbox.
- No agregar dominio personalizado al sandbox (DNS de Google Cloud intacto).
- No dar la URL del sandbox a clientes o prospectos: para eso está
  demo.kuramas.com.

## 10. Archivos que forman parte de esto

| Archivo | Qué hace |
|---|---|
| `.github/workflows/deploy.yml` | Mismo pipeline para `main` (production) y `staging` (sandbox); guardias anti-cruce; demo sólo en main |
| `.github/workflows/sandbox-seed.yml` | Siembra / re-siembra los datos sintéticos del sandbox (manual) |
| `supabase/seed/seed_sandbox.sql` | Centros de prueba, 7 cuentas, catálogo, hospital, cuidadores; se niega a correr si `kt.env ≠ 'sandbox'` |
| `supabase/seed/seed_synthetic_patients.sql` | Los 6 pacientes del motor; ahora compatible con multi-centro (`organization_id`) y parametrizable con `kt.seed_org_id` / `kt.seed_staff_id` |
| `lib/core/config/app_config.dart` | `AppConfig.appEnv` / `AppConfig.isSandbox` (dart-define `APP_ENV`) |
| `lib/main.dart` | `SandboxBanner`: franja naranja sólo cuando `APP_ENV=sandbox` |
