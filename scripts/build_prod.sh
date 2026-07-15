#!/usr/bin/env bash
# Reconstruye el build de PRODUCCIÓN real (build/web, puerto 3000, pm2
# kuratracker-web) con las credenciales reales de Supabase.
#
# Requiere las variables de entorno SUPABASE_URL y SUPABASE_ANON_KEY ya
# exportadas en el shell (nunca hardcodeadas en este archivo ni en el repo).
#
# Uso:
#   export SUPABASE_URL="https://<project-ref>.supabase.co"
#   export SUPABASE_ANON_KEY="<anon-key>"
#   ./scripts/build_prod.sh
#
# Al terminar, reinicia pm2 kuratracker-web y verifica con curl.

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "ERROR: exporta SUPABASE_URL y SUPABASE_ANON_KEY antes de correr este script." >&2
  exit 1
fi

echo "==> flutter build web --release -o build/web (CON dart-define de Supabase)"
flutter build web --release -o build/web \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

echo "==> verificando que el bundle tiene la URL de Supabase"
if ! grep -q "$(echo "$SUPABASE_URL" | sed -E 's#^https?://##')" build/web/main.dart.js; then
  echo "ERROR: no se encontró la URL de Supabase en build/web/main.dart.js" >&2
  exit 1
fi
if grep -q "Cuentas de demostraci" build/web/main.dart.js; then
  echo "ERROR: el bundle parece estar en modo demo (se encontró el fingerprint de demo)." >&2
  exit 1
fi
echo "✅ Bundle verificado: contiene la URL de Supabase real y no el fingerprint de demo."

echo "==> reiniciando pm2 kuratracker-web"
pm2 restart kuratracker-web

sleep 2
echo "==> curl de verificación"
curl -s -o /dev/null -w "  /          -> http:%{http_code}\n" http://localhost:3000/
curl -s -o /dev/null -w "  /patients  -> http:%{http_code}\n" http://localhost:3000/patients

echo ""
echo "✅ Producción reconstruida y verificada."
