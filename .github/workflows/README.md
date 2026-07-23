# CI / GitHub Actions

## deploy.yml — deploy completo (reemplazo de Genspark)

En cada **push a `main`** (o manual desde Actions → "Deploy…" → Run workflow):

1. **Migraciones**: `supabase db push` aplica las migraciones pendientes de
   `supabase/migrations/` (idempotente; solo aplica las nuevas, en orden).
2. **Build + deploy** (solo si las migraciones pasaron): compila con **Flutter
   3.27.1** y publica en Cloudflare Pages:
   - **prod** (`kuratracker-prod`) con las credenciales reales de Supabase
     (`--dart-define`).
   - **demo** (`kuratracker-demo`) sin credenciales (modo local/sintético).

Si las migraciones fallan, la app **no** se despliega (no se publica una versión
que espera columnas que aún no existen).

### Configurar una sola vez — Secrets

GitHub → Settings → Secrets and variables → Actions → **New repository secret**:

| Secret | De dónde |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | supabase.com/dashboard/account/tokens |
| `SUPABASE_PROJECT_REF` | Supabase → Project Settings → General |
| `SUPABASE_DB_PASSWORD` | Supabase → Project Settings → Database |
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase → Project Settings → API (anon/publishable) |
| `CLOUDFLARE_API_TOKEN` | Cloudflare → My Profile → API Tokens → permiso "Cloudflare Pages: Edit" |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard (barra lateral / URL) |

> La `anon key` es pública por diseño (va en el bundle del cliente y la protege
> la RLS); como *secret* no queda en el repo.

### Aprobación manual (opcional, recomendado)

Settings → Environments → crea `production` → "Required reviewers". Así cada
deploy pide tu aprobación antes de tocar la BD y publicar.

### ⚠️ Primera vez — sincronizar el historial de migraciones

`supabase db push` solo funciona si el historial remoto
(`supabase_migrations.schema_migrations`) refleja lo ya aplicado. Como las
migraciones previas (0001–0040) se aplicaron a mano/por Management API, puede
que NO estén registradas y `db push` intente re-aplicarlas y falle.

Reconciliar UNA sola vez (Actions → "Supabase migrations" manual, o local con
la CLI):

```
supabase migration list --linked      # ver cuáles figuran como aplicadas
# marcar como aplicadas las que YA corriste a mano (ej. hasta 0040):
supabase migration repair --status applied 0001 0002 ... 0040
```

Después, `db push` solo aplicará las nuevas (0041 en adelante) y el pipeline
queda 100% automático.

## supabase-migrations.yml — migraciones manuales (respaldo)

Solo disparo **manual** (Actions → "Supabase migrations" → Run workflow) para
aplicar migraciones sin desplegar la app. El disparo automático en push vive
ahora en `deploy.yml`.
