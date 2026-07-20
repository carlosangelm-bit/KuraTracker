#!/usr/bin/env bash
# Reconstruye el build de DEMO (build/web-demo, puerto 3001, pm2
# kuratracker-web-demo) SIN credenciales de Supabase: la app corre en modo
# local/sintético (datos de ejemplo precargados), sin tocar producción.
#
# Correr este script cada vez que se reconstruye producción, para que el demo
# no se quede atrás respecto a main (ver historial: el demo se olvidaba en los
# deploys que solo corrían build_prod.sh).
#
# Uso:
#   ./scripts/build_demo.sh
#
# Al terminar, reinicia pm2 kuratracker-web-demo y verifica con curl.

set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> flutter build web --release -o build/web-demo (SIN dart-define: modo demo)"
flutter build web --release -o build/web-demo

echo "==> verificando que el bundle está en modo DEMO"
# En modo demo la app muestra el fingerprint de cuentas de demostración; si NO
# aparece, probablemente se compiló con credenciales por error.
if ! grep -q "Cuentas de demostraci" build/web-demo/main.dart.js; then
  echo "ERROR: build/web-demo no parece estar en modo demo (falta el fingerprint)." >&2
  exit 1
fi
echo "✅ Bundle de demo verificado (modo local/sintético)."

echo "==> reiniciando pm2 kuratracker-web-demo"
pm2 restart kuratracker-web-demo

sleep 2
echo "==> curl de verificación (puerto 3001)"
curl -s -o /dev/null -w "  /          -> http:%{http_code}\n" http://localhost:3001/
curl -s -o /dev/null -w "  /patients  -> http:%{http_code}\n" http://localhost:3001/patients

echo ""
echo "✅ Demo reconstruido y verificado."
