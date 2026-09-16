#!/usr/bin/env bash
# Corre TODA la cobertura SQL del protocolo contra un Postgres real: el candado/vigencia/
# aislamiento/huérfanas (protocol_catalog_local_tests) y la CONDUCTA de resolve_protocol con
# salidas esperadas a mano (resolve_protocol_behavior). ON_ERROR_STOP=1 + `raise exception` en
# cada aserción → si algo falla, psql sale ≠0 y este script (set -e) revienta → el job de CI
# se pone rojo. Es la ÚNICA cobertura continua de la resolución de producto clínico una vez que
# se retire el resolvedor de Dart (etapa 3).
#
# Conexión: si PGHOST está definido (CI: servicio postgres), usa psql directo; si no (local),
# levanta un Postgres desechable en Docker.  Uso local:  supabase/tests/local/run_sql_tests.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."

if [ -n "${PGHOST:-}" ]; then
  export PGPASSWORD="${PGPASSWORD:-pw}"
  psql() { command psql -h "$PGHOST" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" \
                 -d "${PGDATABASE:-kt}" -v ON_ERROR_STOP=1 "$@"; }
else
  C=kt-pg-sqltests
  docker rm -f "$C" >/dev/null 2>&1 || true
  docker run -d --name "$C" -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=kt -p 55477:5432 postgres:15 >/dev/null
  trap 'docker rm -f "$C" >/dev/null 2>&1 || true' EXIT
  for _ in $(seq 1 30); do docker exec "$C" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done
  psql() { docker exec -i "$C" psql -U postgres -d kt -v ON_ERROR_STOP=1 "$@"; }
fi

for f in \
  supabase/tests/local/protocol_catalog_fixture.sql \
  supabase/migrations/0076_protocol_product_rules.sql \
  supabase/migrations/0077_protocol_rule_conditions.sql \
  supabase/migrations/0136_protocol_catalog_matrix_schema.sql \
  supabase/migrations/0137_protocol_catalog_admin_only.sql \
  supabase/migrations/0138_org_entitlement_vigente.sql \
  supabase/migrations/0139_resolve_protocol.sql; do
  psql < "$f" >/dev/null
done

echo "--- candado / vigencia / aislamiento / huérfanas ---"
psql < supabase/tests/local/protocol_catalog_local_tests.sql 2>&1 | grep -E "PASS|FAIL|ALL TESTS PASSED"
echo "--- resolve_protocol · conducta (salidas esperadas a mano) ---"
psql < supabase/tests/local/resolve_protocol_behavior.sql 2>&1 | grep -E "BEHAVIOR PASS|BEHAVIOR FAIL|ALL PASSED"
echo "SQL TESTS OK"
