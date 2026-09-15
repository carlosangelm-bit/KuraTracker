#!/usr/bin/env bash
# Ejecuta contra un Postgres desechable los escritores de filas source='master' que
# viven aquí (backfill de 0114 y create_trial_organization de 0135) y verifica que sus
# filas pasan ent_master_grant_shape (0132). Los otros dos escritores tienen su propio
# arnés: master_grant_entitlement (0132) y la toma Stripe (0133) → run.sh.
set -euo pipefail
cd "$(dirname "$0")/../../.."
C=kt-pg-writers
docker rm -f "$C" >/dev/null 2>&1 || true
docker run -d --name "$C" -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=kt -p 55436:5432 postgres:15 >/dev/null
trap 'docker rm -f "$C" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 30); do docker exec "$C" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done
psql() { docker exec -i "$C" psql -U postgres -d kt -v ON_ERROR_STOP=1 "$@"; }
psql < supabase/tests/local/master_grants_fixture.sql >/dev/null
psql < supabase/tests/local/master_row_writers_pre.sql >/dev/null   # filas de 0114 ANTES de 0132
psql < supabase/migrations/0132_master_grants.sql >/dev/null         # rellena 0114 + CHECK
psql < supabase/tests/local/master_row_writers_setup.sql >/dev/null
psql < supabase/migrations/0135_trial_org_grant_shape.sql >/dev/null
echo "--- escritores de filas master vs ent_master_grant_shape ---"
psql < supabase/tests/local/master_row_writers_local_tests.sql 2>&1 | grep -E "PASS|FAIL|ALL WRITERS"
