# CI / GitHub Actions

## supabase-migrations.yml — aplicar migraciones a Supabase

Aplica `supabase/migrations/*.sql` al proyecto de Supabase (prod) con
`supabase db push`:

- **Automático**: en cada push a `main` que toque `supabase/migrations/**`.
- **Manual**: pestaña Actions → "Supabase migrations" → Run workflow.

`db push` solo aplica migraciones **pendientes**, en orden numérico, y registra
lo aplicado en el schema `supabase_migrations` (no re-aplica ni borra nada).

### Configurar una sola vez

1. **Secrets** en GitHub → Settings → Secrets and variables → Actions → New:
   - `SUPABASE_ACCESS_TOKEN` — token personal (supabase.com/dashboard/account/tokens).
   - `SUPABASE_PROJECT_REF` — ref del proyecto (Project Settings → General).
   - `SUPABASE_DB_PASSWORD` — contraseña de la BD (Project Settings → Database).
2. **(Opcional, recomendado) Aprobación manual**: Settings → Environments →
   crea `production` → "Required reviewers". Así cada aplicación de migraciones
   pide aprobación antes de correr.

### Notas

- La primera vez, verifica que las migraciones ya aplicadas manualmente queden
  reconocidas: si `db push` intenta re-aplicar una que ya corriste a mano,
  puede fallar. En ese caso, marca esa versión como aplicada con
  `supabase migration repair --status applied <version>` (una sola vez).
- No corre `flutter build/test` — es solo migraciones de BD.
