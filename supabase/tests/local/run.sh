#!/usr/bin/env bash
# Corre las pruebas 1-4 de las RPC master_* (0132) contra el CÓDIGO REAL de la
# migración, en un Postgres desechable en Docker, con un fixture MÍNIMO (solo lo que
# 0132 toca/referencia). No necesita el stack de Supabase ni la cadena completa de
# migraciones. Es el arnés con el que se verificó a mano que cada prueba se pone en
# ROJO al quitar su guardia (§6). El artefacto que corre en el SANDBOX real es
# ../master_grants_acceptance_sandbox.sql.
#
# Uso:  supabase/tests/local/run.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."   # raíz del repo

C=kt-pg-mastergrants
docker rm -f "$C" >/dev/null 2>&1 || true
docker run -d --name "$C" -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=kt -p 55432:5432 postgres:15 >/dev/null
trap 'docker rm -f "$C" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 30); do docker exec "$C" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done

psql() { docker exec -i "$C" psql -U postgres -d kt -v ON_ERROR_STOP=1 "$@"; }

psql < supabase/tests/local/master_grants_fixture.sql >/dev/null
psql < supabase/migrations/0132_master_grants.sql >/dev/null
psql < supabase/migrations/0133_stripe_takeover_clears_master_fields.sql >/dev/null
echo "--- 0132: pruebas 1-4 (§6) ---"
psql < supabase/tests/local/master_grants_local_tests.sql 2>&1 | grep -E "PASS|FAIL|ALL TESTS"
echo "--- 0133: ida y vuelta + cancelada/activa ---"
psql < supabase/tests/local/stripe_takeover_local_tests.sql 2>&1 | grep -E "PASS|FAIL|PASSED"
