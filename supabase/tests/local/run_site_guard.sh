#!/usr/bin/env bash
# Corre los tres rechazos + el caso positivo de 0134 (guardia de desactivación de
# sitios) contra el CÓDIGO REAL de la migración, en un Postgres desechable en Docker,
# con un fixture MÍNIMO (solo sites/staff/inventory_movements). No necesita el stack de
# Supabase ni la cadena completa de migraciones. Es el arnés con el que se verificó a
# mano que cada rechazo se pone en ROJO al quitar su rama de la guardia.
#
# Uso:  supabase/tests/local/run_site_guard.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."   # raíz del repo

C=kt-pg-siteguard
docker rm -f "$C" >/dev/null 2>&1 || true
docker run -d --name "$C" -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=kt -p 55433:5432 postgres:15 >/dev/null
trap 'docker rm -f "$C" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 30); do docker exec "$C" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done

psql() { docker exec -i "$C" psql -U postgres -d kt -v ON_ERROR_STOP=1 "$@"; }

psql < supabase/tests/local/site_guard_fixture.sql >/dev/null
psql < supabase/migrations/0134_prevent_site_deactivation.sql >/dev/null
echo "--- 0134: tres rechazos + caso positivo (§5) ---"
psql < supabase/tests/local/site_guard_local_tests.sql 2>&1 | grep -E "PASS|FAIL|ALL TESTS"
