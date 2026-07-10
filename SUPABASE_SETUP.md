# SUPABASE_SETUP.md — Runbook de conexión a Supabase real

Guía paso a paso para que **tú** (dueño del proyecto Supabase) apliques el
esquema de KuraTracker, crees el primer usuario admin y verifiques que Row
Level Security (RLS) funciona correctamente — **antes** de pasarme la
`anon key` para el smoke-test de la app y **antes** de correr el seed de
pacientes sintéticos.

> 🔒 **Regla de oro de todo este documento**: la app Flutter (cliente) usa
> **únicamente** la `anon` / `publishable` key. La `service_role` key
> (`SUPABASE_SECRET_KEY` en tu export) **nunca** se usa en el cliente, nunca
> se pega en el chat, y nunca se sube al repo. Solo tú la usas, y solo si
> algún día necesitas un script de administración fuera del navegador.

> ✅ **Estado en el proyecto piloto (actualizado):** las secciones 1–3 de
> este runbook ya se completaron en el proyecto Supabase real del piloto
> (4 migraciones aplicadas 0001→0004, usuario admin creado y promovido).
> En el camino se encontró y corrigió un bug real de `search_path` en
> funciones `SECURITY DEFINER` de la migración 0002 — ver
> `supabase/hotfixes/0002_fix_search_path.sql` y la fila correspondiente en
> la sección 8 (Problemas comunes). Ese fix ya quedó incorporado también en
> `0002_triggers_and_functions.sql` para que un proyecto nuevo (ej.
> producción) no lo sufra al aplicar las migraciones desde cero. El resto
> de este documento (secciones 4+) sigue siendo la referencia vigente para
> la verificación de RLS pendiente y para futuros entornos.

---

## 0. Qué vas a terminar teniendo

Al final de este runbook:

- [ ] Proyecto Supabase propio, con las 4 migraciones aplicadas (esquema,
      triggers, RLS, storage).
- [ ] Un usuario admin real (tu correo) con `profiles.role = 'admin'`.
- [ ] RLS verificado con al menos 2 pruebas (admin ve todo / un clínico
      normal solo vería lo suyo).
- [ ] La `anon key` y la `URL` del proyecto, listas para pasarme (paso 6).

Lo que **no** haces todavía en este runbook (vienen después, en orden):

- Correr el seed de pacientes sintéticos (`supabase/seed/seed_synthetic_patients.sql`)
  — lo harás tú mismo **después** de verificar RLS, como acordamos.
- Conectar el build de Flutter (`--dart-define`) — lo hago yo en cuanto me
  pases la `anon key` + `URL`.

---

## 1. Crear el proyecto Supabase

1. Entra a [supabase.com](https://supabase.com) con **tu** cuenta (la que
   será dueña del proyecto — no la mía, no una cuenta compartida).
2. **New project** → elige organización, nombre (sugerido: `kuratracker-piloto`
   o `curamas-kuratracker`), contraseña de base de datos (guárdala en un
   gestor de contraseñas, la necesitarás poco pero es la llave maestra de
   Postgres), región (elige la más cercana a México, ej. `us-east-1` o
   `sa-east-1` si está disponible).
3. Espera 1–2 minutos a que el proyecto termine de aprovisionarse.

---

## 2. Aplicar las 4 migraciones (orden obligatorio)

### 2.1 Por qué el orden es estricto

| # | Archivo | Qué crea | Depende de |
|---|---|---|---|
| **0001** | `supabase/migrations/0001_core_schema.sql` | Extensión `pgcrypto`, tipos enum, y **todas** las tablas (`profiles`, `sites`, `staff`, `patients`, `wounds`, `consultations`, `treatment_plans`, `kura_recommendations`, etc.) | Nada — es la base |
| **0002** | `supabase/migrations/0002_triggers_and_functions.sql` | Triggers de folio automático (`PA2026-0001`, `K2024-0001`), trigger `updated_at`, trigger de auditoría, trigger `handle_new_auth_user` (crea `profiles` al registrar un usuario en `auth.users`), y las funciones helper `is_admin()` / `current_staff_id()` / `current_user_role()` | Necesita que las tablas de 0001 ya existan |
| **0003** | `supabase/migrations/0003_row_level_security.sql` | Activa RLS en las 18 tablas clínicas y define todas las políticas (`admin ve todo`, `clínico solo ve lo asignado`) | Necesita las tablas de 0001 **y** las funciones `is_admin()`/`current_staff_id()` de 0002 (las políticas las invocan directamente) |
| **0004** | `supabase/migrations/0004_storage_buckets.sql` | Crea el bucket `wound-evidence` (privado, límite 17 MB por archivo) y sus políticas de storage | Necesita `is_admin()`/`current_staff_id()` de 0002; conceptualmente depende de que `wounds`/`staff_patient_assignments` (0001) ya existan |

Si corres 0003 antes de 0002, falla con `function public.is_admin() does not
exist`. Si corres 0002 antes de 0001, falla con `relation public.staff does
not exist`. Por eso: **siempre 0001 → 0002 → 0003 → 0004, sin saltar ni
invertir.**

### 2.2 Cómo aplicarlas (SQL Editor — recomendado para este piloto)

No necesitas instalar la CLI de Supabase ni Docker. Usa el **SQL Editor**
del dashboard:

1. En el dashboard de tu proyecto → menú lateral → **SQL Editor** → **New
   query**.
2. Abre `supabase/migrations/0001_core_schema.sql` en el repo, copia **todo**
   el contenido, pégalo en el editor, click **Run**.
   - Debe terminar con `Success. No rows returned` (o similar). Si ves un
     error, detente y revísalo antes de continuar — no sigas con 0002.
3. **New query** otra vez → copia/pega **todo** `0002_triggers_and_functions.sql`
   → **Run**.
4. **New query** → copia/pega **todo** `0003_row_level_security.sql` →
   **Run**.
5. **New query** → copia/pega **todo** `0004_storage_buckets.sql` → **Run**.

Después de las 4, verifica rápido en **Table Editor** que aparezcan las
tablas (`profiles`, `patients`, `wounds`, `treatment_plans`,
`kura_recommendations`, etc.) y en **Storage** que exista el bucket
`wound-evidence` (privado).

> 💡 Si necesitas re-aplicar una migración desde cero (por ejemplo, te
> equivocaste de orden), lo más simple en esta etapa de piloto es borrar el
> proyecto y crear uno nuevo, o pedirme ayuda para escribir un script de
> "reset" — las migraciones tal como están escritas **no** son
> auto-idempotentes (usan `create table`, no `create table if not exists`
> en todos los casos), a propósito, para que un `Run` accidental duplicado
> te avise con un error en vez de fallar en silencio.

---

## 3. Crear tu usuario admin

Las migraciones **no** crean ningún usuario — eso lo haces tú, para no
tener credenciales de ejemplo hardcodeadas en el repo.

### 3.1 Registrar el usuario en Auth

Opción A — desde el dashboard (más simple, recomendada):

1. Dashboard → **Authentication** → **Users** → **Add user** → **Create new
   user**.
2. Pon tu correo real y una contraseña. Marca **Auto Confirm User** (así no
   necesitas configurar SMTP todavía para el piloto).
3. Click **Create user**.

Esto dispara automáticamente el trigger `handle_new_auth_user` (de la
migración 0002), que crea una fila en `public.profiles` con
`role = 'clinico'` por default (el trigger no sabe que tú eres admin — eso
lo corriges en el siguiente paso).

### 3.2 Promoverte a admin

1. **SQL Editor** → **New query**:
   ```sql
   update public.profiles
   set role = 'admin'
   where email = 'TU_CORREO_AQUI@ejemplo.com';
   ```
2. **Run**. Debe decir `1 row affected` (si dice `0`, revisa que el correo
   esté escrito exactamente igual que en Authentication → Users).
3. Verifica:
   ```sql
   select id, email, role, full_name from public.profiles;
   ```
   Debe aparecer tu fila con `role = admin`.

> Nota: `profiles.role = 'admin'` es el rol de **aplicación** (permisos
> dentro de KuraTracker). Es independiente del rol de **Postgres**
> (`postgres`, `service_role`, `authenticated`, `anon`) que maneja
> Supabase internamente — no los confundas.

---

## 4. Verificar RLS (antes de avanzar)

Esta es la parte que **no debes saltarte**: confirmar que las políticas de
la migración 0003 realmente restringen el acceso como se espera, no solo que
"no dieron error al crearse".

### 4.1 Prueba rápida desde el SQL Editor (como `postgres`, bypassa RLS — solo para ver los datos crudos)

El SQL Editor por default corre como el rol `postgres`, que **bypassa RLS**
(por eso el seed también se corre ahí). Esto es útil para *poblar* datos,
pero **no** sirve para probar RLS — necesitas probar como lo haría la app
real, autenticado con la `anon key`.

### 4.2 Prueba real de RLS — usando el cliente API/REST autenticado

La forma más fiel a como se comporta la app es usar el endpoint REST de
Supabase con un JWT de usuario real. Puedes hacerlo con `curl` desde
cualquier terminal (no necesitas el sandbox ni Flutter):

**a) Obtén un access_token iniciando sesión como tu usuario admin:**

```bash
curl -X POST 'https://TU_PROYECTO.supabase.co/auth/v1/token?grant_type=password' \
  -H "apikey: TU_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"TU_CORREO_AQUI@ejemplo.com","password":"TU_PASSWORD"}'
```

Copia el valor de `"access_token"` de la respuesta.

**b) Con ese token, intenta leer `patients` (debería funcionar, sin filas
todavía porque no has corrido el seed):**

```bash
curl 'https://TU_PROYECTO.supabase.co/rest/v1/patients?select=*' \
  -H "apikey: TU_ANON_KEY" \
  -H "Authorization: Bearer EL_ACCESS_TOKEN_DEL_PASO_A"
```

Como eres `admin`, debe responder `[]` (array vacío, sin error 401/403).
Si responde con un error de permisos, algo falló en la migración 0003 —
detente aquí y revisamos juntos antes de seguir.

**c) Prueba negativa (opcional pero recomendable): crea un segundo usuario
de prueba SIN promoverlo a admin y SIN asignarle pacientes**, repite el
login (paso a) con ese usuario, y repite la lectura de `patients` (paso b)
con su token. Como es `clinico` sin asignaciones, debe responder `[]`
también (RLS lo filtra a "cero pacientes visibles", no un error — así está
diseñado). Esto confirma que la política `patients_select` realmente está
filtrando y no dejando pasar todo por accidente.

> Si en el paso (c) el usuario sin asignaciones **ve pacientes** (una vez
> que existan, después del seed), eso significaría que RLS no está
> activo o las políticas no están bien — repórtamelo inmediatamente, no
> avances a producción con ese proyecto.

### 4.3 Checklist de verificación RLS

- [ ] Login con `apikey` + `email`/`password` devuelve `access_token` sin
      error.
- [ ] Lectura de `/rest/v1/patients` autenticado como admin no da error
      401/403.
- [ ] (Opcional pero recomendado) Un usuario `clinico` sin asignaciones lee
      `/rest/v1/patients` y obtiene `[]`, no un error ni todos los
      pacientes.
- [ ] En **Storage → wound-evidence**, el bucket aparece como **privado**
      (no público) — confírmalo visualmente en el dashboard.

Cuando los 4 puntos estén ✅, ya podemos avanzar.

---

## 5. Dónde encontrar tu URL y tu anon key

Dashboard de tu proyecto → **Project Settings** (ícono de engranaje) →
**API**:

- **Project URL** → esto es tu `SUPABASE_URL` (ej.
  `https://abcdefghijk.supabase.co`).
- **Project API keys** → la fila marcada **`anon` `public`** (a veces
  etiquetada como "publishable") → esto es tu `SUPABASE_ANON_KEY`.

> ⚠️ En esa misma pantalla vas a ver también una key marcada **`service_role`
> `secret`**. **Esa NO la necesito, no la pegues en el chat, no la pongas en
> ningún archivo del repo.** Es la llave que bypassa RLS por completo — si
> se filtra, cualquiera con ella tiene acceso total a los datos clínicos sin
> restricción. Consérvala solo en tu gestor de contraseñas personal.

---

## 6. Qué me pasas cuando termines

Solo dos valores, cuando ya verificaste RLS (sección 4):

```
SUPABASE_URL=https://tu-proyecto.supabase.co
SUPABASE_ANON_KEY=eyJ... (la publishable/anon, NO la service_role)
```

Con eso yo hago:

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=https://tu-proyecto.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

y corro el smoke-test (login con tu usuario admin real, navegación básica)
para confirmar que la app conecta correctamente contra tu proyecto antes de
que tú corras el seed.

> ✅ **Smoke-test completado en el proyecto piloto (2026-07-10).** Con la
> cuenta de prueba `smoketest@curamas.mx` (que promoviste a `role='admin'`
> vía SQL Editor) verifiqué end-to-end, contra tu proyecto Supabase real:
> login → crear paciente (folio auto-generado `PA2026-0001`) → captura
> (herida + evaluación + medición + perfusión) → tratamiento con sugerencia
> Kura+ (escenario A, `A1 - Cierre Activo`) → **seguimiento** (segunda
> consulta + segunda medición con reducción de área 5.0→0.9cm² = 82% →
> checkpoint de Sheehan `confirmar_cierre`) → **reporte** (confirmé que
> todo el árbol de datos que alimenta el PDF —paciente, ambas consultas,
> herida, ambas mediciones, plan de tratamiento, recomendación Kura+ y
> checkpoint Sheehan— se lee correctamente vía RLS con este usuario).
>
> **Nota metodológica importante**: esta verificación se hizo reproduciendo
> exactamente las mismas llamadas REST (Postgrest) que `DataRepository` /
> `SupabaseDataStore` usan internamente en la app Flutter, autenticado como
> el usuario de prueba real — no fue un test de clics literal en el
> navegador (mis herramientas de automatización solo cargan la página y
> capturan la consola, no simulan clics/formularios). Es la validación más
> fuerte disponible del pipeline de datos completo (RLS + triggers +
> constraints + esquema), pero no sustituye una revisión visual manual de
> cada pantalla, que te recomiendo hacer tú mismo con el build ya conectado.
>
> Como beneficio adicional, este smoke-test también validó en producción
> real el fix de seguridad de la sección 8 (`search_path`): el `profiles`
> del usuario de prueba se creó correctamente vía `handle_new_auth_user()`,
> y `audit_trigger_fn()` generó su entrada de auditoría al crear el
> paciente — ambas funciones corregidas.
>
> **Datos de prueba creados** (quedan en tu proyecto, claramente marcados):
> `staff` folio `K2026-SMOKE1`, `patients` folio `PA2026-0001` ("Paciente
> Smoketest (borrar)"), `sites` "Kura+ Piloto (smoketest)", más las
> consultas/heridas/mediciones/plan/recomendación/checkpoint asociados.
> **Recomendación**: bórralos desde el SQL Editor antes de correr el seed
> (para no confundir `PA2026-0001` con los folios `SEED-PA2026-000x` del
> seed real) — por ejemplo `delete from public.patients where folio =
> 'PA2026-0001';` (el `on delete cascade` del esquema se encarga del resto).
> Si prefieres dejarlos como referencia, no hay conflicto técnico real
> porque el seed usa el prefijo `SEED-`.

---

## 7. Después del smoke-test: tú corres el seed

Una vez que confirme que el smoke-test pasó, el siguiente paso es que **tú**
corras `supabase/seed/seed_synthetic_patients.sql` desde el SQL Editor (no
desde la app) — el archivo ya incluye sus propias instrucciones en el
encabezado (requiere que exista tu usuario admin, es idempotente, y al
final te dice cómo reasignar los pacientes de prueba de un "staff semilla"
a tu usuario real si quieres verlos en tu propia sesión). Te aviso en ese
momento con el detalle exacto.

---

## 8. Problemas comunes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `relation "public.staff" does not exist` al correr 0002 | Corriste 0002 antes de 0001, o 0001 falló a medias | Revisa que 0001 haya corrido completo con éxito antes de reintentar 0002 |
| `function public.is_admin() does not exist` al correr 0003 | Corriste 0003 antes de 0002 | Corre 0002 completo primero |
| `permission denied for table patients` al leer desde `curl`/app | RLS activo pero no tienes `profiles.role='admin'` ni asignación en `staff_patient_assignments` | Verifica la sección 3.2 (promoción a admin) |
| **"Database error creating new user"** al hacer Authentication → Add user (el error real en **Postgres logs** dice `type "user_role" does not exist`) | **Bug corregido — detectado en el piloto.** `handle_new_auth_user()` (y las otras funciones `SECURITY DEFINER` de 0002) referenciaban `user_role` sin calificar por esquema. El trigger corre bajo el rol interno `supabase_auth_admin`, que no tiene `public` en su `search_path`, así que no resolvía el tipo aunque `public.user_role` sí existiera. | Si tu proyecto ya tiene las migraciones aplicadas (como el caso del piloto): corre `supabase/hotfixes/0002_fix_search_path.sql` desde el SQL Editor (seguro de re-ejecutar, solo reemplaza cuerpos de función, no toca triggers). Si es un proyecto **nuevo**, ya no te afecta: el fix está incorporado directamente en `0002_triggers_and_functions.sql`. |
| El usuario nuevo no aparece en `profiles` tras crearlo en Authentication | El trigger `handle_new_auth_user` no corrió (falta 0002), falló silenciosamente, o es el bug de `search_path` de arriba | Revisa Postgres Logs para el error exacto; si es el bug de `search_path`, aplica el hotfix de la fila anterior |
| Bucket `wound-evidence` no aparece en Storage | 0004 no se aplicó, o se aplicó con error | Re-revisa el resultado del `Run` de 0004 en el SQL Editor |
| Quiero "resetear" y volver a empezar | Las migraciones no son 100% idempotentes por diseño | Lo más simple en esta etapa: crear un proyecto Supabase nuevo y repetir el runbook; o pídeme un script de limpieza si prefieres reusar el mismo proyecto |

> 💡 **Dónde ver el error real de Postgres** (no solo el mensaje genérico del
> dashboard de Auth): Dashboard → **Logs** → **Postgres Logs**, filtra por la
> hora en que intentaste crear el usuario. El dashboard de Authentication
> suele mostrar un mensaje genérico ("Database error creating new user")
> que oculta la causa real — siempre revisa Postgres Logs para triggers que
> fallan en `auth.users`.

---

## 9. Resumen del flujo completo (referencia rápida)

```
1. Crear proyecto Supabase (tú, dueño de la cuenta)
2. SQL Editor: correr 0001 → 0002 → 0003 → 0004 (en ese orden, uno a la vez)
3. Authentication → Add user (tu correo) + Auto Confirm
4. SQL Editor: update profiles set role='admin' where email=...
5. Verificar RLS con curl (login + lectura /rest/v1/patients)
6. Pasarme SUPABASE_URL + SUPABASE_ANON_KEY (nunca la service_role)
7. (Yo) build --dart-define + smoke-test
8. (Tú) correr supabase/seed/seed_synthetic_patients.sql desde SQL Editor
9. Verificación clic-a-clic completa contra datos sembrados
```
