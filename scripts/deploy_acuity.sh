#!/usr/bin/env bash
# Despliega el backend de la integración con Acuity Scheduling en Supabase:
# secrets + las 5 Edge Functions. Los pasos manuales que quedan (webhooks en
# Acuity, mapeo/creación de usuarios, backfill, Realtime, SMTP) se imprimen al
# final.
#
# Requiere:
#   - Supabase CLI instalado y el proyecto enlazado (supabase link).
#   - Variables de entorno con las credenciales de Acuity (NUNCA hardcodeadas):
#       export ACUITY_USER_ID="18477413"
#       export ACUITY_API_KEY="<tu-api-key>"
#
# Uso:
#   export ACUITY_USER_ID=... ACUITY_API_KEY=...
#   ./scripts/deploy_acuity.sh
#
# Todo esto corre contra tu proyecto Supabase de PRODUCCIÓN; no toca el modo demo.

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ACUITY_USER_ID:-}" || -z "${ACUITY_API_KEY:-}" ]]; then
  echo "ERROR: exporta ACUITY_USER_ID y ACUITY_API_KEY antes de correr este script." >&2
  exit 1
fi

if ! command -v supabase >/dev/null 2>&1; then
  echo "ERROR: falta el Supabase CLI (https://supabase.com/docs/guides/cli)." >&2
  exit 1
fi

echo "==> 1/2 Guardando secrets de Acuity en Supabase"
supabase secrets set \
  ACUITY_USER_ID="$ACUITY_USER_ID" \
  ACUITY_API_KEY="$ACUITY_API_KEY"

echo "==> 2/2 Desplegando Edge Functions"
supabase functions deploy acuity-proxy
supabase functions deploy acuity-webhook --no-verify-jwt   # Acuity no manda JWT
supabase functions deploy acuity-backfill
supabase functions deploy acuity-sync-calendars

cat <<'NEXT'

✅ Secrets + Edge Functions desplegados.

Pasos manuales que faltan (ver supabase/functions/README.md):

  1. Migración aplicada (0016) — si aún no: `supabase db push`.

  2. Realtime en la tabla (SQL Editor), para que la app vea las citas en vivo:
       alter publication supabase_realtime add table public.appointments;

  3. SMTP/email en Supabase (Auth → Email) para que salgan las invitaciones
     al crear usuarios.

  4. Webhooks en Acuity (Integrations → Webhooks): pega la MISMA URL en
     "New scheduled", "Rescheduled" y "Canceled":
       https://<PROJECT_REF>.supabase.co/functions/v1/acuity-webhook

  5. Mapear/crear Kuradores por email (organizationId de Kura+ = select id,name from organizations):
       # solo mapear existentes:
       curl -X POST '.../functions/v1/acuity-sync-calendars' -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
       # crear los que falten (con login):
       curl -X POST '.../functions/v1/acuity-sync-calendars' -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
            -H "Content-Type: application/json" -d '{"createMissing":true,"organizationId":"<UUID_KURA+>"}'

  6. Backfill de citas existentes:
       curl -X POST '.../functions/v1/acuity-backfill' -H "Authorization: Bearer <SERVICE_ROLE_KEY>"

  7. Verificar en KuraTracker (build de producción con Supabase) → pestaña Agenda.
NEXT
