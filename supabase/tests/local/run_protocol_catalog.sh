#!/usr/bin/env bash
# Corre las pruebas de 0136 (Matriz del protocolo, etapa 1: esquema + candado) contra el
# CÓDIGO REAL de las migraciones, en un Postgres desechable en Docker, con un fixture
# MÍNIMO (solo lo que 0076/0077/0136 tocan/referencian). No necesita el stack de Supabase.
# Con esto se verifica a mano que cada prueba se pone en ROJO al quitar su guardia.
#
# Uso:  supabase/tests/local/run_protocol_catalog.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."   # raíz del repo

C=kt-pg-protocolcatalog
docker rm -f "$C" >/dev/null 2>&1 || true
docker run -d --name "$C" -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=kt -p 55433:5432 postgres:15 >/dev/null
trap 'docker rm -f "$C" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 30); do docker exec "$C" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done

psql() { docker exec -i "$C" psql -U postgres -d kt -v ON_ERROR_STOP=1 "$@"; }

psql < supabase/tests/local/protocol_catalog_fixture.sql >/dev/null
psql < supabase/migrations/0076_protocol_product_rules.sql >/dev/null
psql < supabase/migrations/0077_protocol_rule_conditions.sql >/dev/null
psql < supabase/migrations/0136_protocol_catalog_matrix_schema.sql >/dev/null
psql < supabase/migrations/0137_protocol_catalog_admin_only.sql >/dev/null
psql < supabase/migrations/0138_org_entitlement_vigente.sql >/dev/null
psql < supabase/migrations/0139_resolve_protocol.sql >/dev/null
echo "--- 0136: candado RLS (protocol:author) + guarda de deriva de esquemas ---"
psql < supabase/tests/local/protocol_catalog_local_tests.sql 2>&1 | grep -E "PASS|FAIL|ALL TESTS PASSED"
