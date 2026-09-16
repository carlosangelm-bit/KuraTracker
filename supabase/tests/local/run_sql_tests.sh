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
  supabase/migrations/0139_resolve_protocol.sql \
  supabase/migrations/0140_protocol_catalog_identity.sql; do
  psql < "$f" >/dev/null
done

echo "--- candado / vigencia / aislamiento / huérfanas ---"
psql < supabase/tests/local/protocol_catalog_local_tests.sql 2>&1 | grep -E "PASS|FAIL|ALL TESTS PASSED"

# CONDICIÓN 1 (etapa 3.5): el corpus de reglas propias es UN SOLO archivo, leído por esta
# prueba de SQL y por la del resolvedor de demo. Se carga aquí a la tabla corpus_json (una fila,
# jsonb) para que resolve_protocol_behavior.sql lo lea. jq compacta el JSON a una línea (para
# \copy en formato TEXT); si no hay jq, python hace lo mismo.
psql -c "drop table if exists corpus_json; create table corpus_json(j jsonb);" >/dev/null
if command -v jq >/dev/null 2>&1; then
  jq -c . supabase/tests/protocol_behavior_corpus.json | psql -c "\copy corpus_json(j) from stdin" >/dev/null
else
  python3 -c "import json,sys; sys.stdout.write(json.dumps(json.load(open('supabase/tests/protocol_behavior_corpus.json'))))" \
    | psql -c "\copy corpus_json(j) from stdin" >/dev/null
fi

echo "--- resolve_protocol · conducta (corpus único + catálogo/contexto/identidad) ---"
psql < supabase/tests/local/resolve_protocol_behavior.sql 2>&1 | grep -E "BEHAVIOR PASS|BEHAVIOR FAIL|ALL PASSED"

# ETAPA 5: se siembra el catálogo real (0141, las 35) y se verifica que un consumidor RESUELVA y
# DEVUELVA filas. Se carga DESPUÉS de la conducta para que las 35 no contaminen esos casos.
psql < supabase/migrations/0141_seed_protocol_catalog_kura_35.sql >/dev/null
echo "--- resolve_protocol · verificación de la siembra (35 → el consumidor resuelve) ---"
psql < supabase/tests/local/resolve_protocol_seed_verify.sql 2>&1 | grep -E "SEED PASS|SEED FAIL|ALL PASSED"
echo "SQL TESTS OK"
