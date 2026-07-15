#!/usr/bin/env bash
# Build-gate de verificación (analyze + test + build web).
#
# IMPORTANTE: este script SIEMPRE compila a build/web-gate (desechable),
# NUNCA a build/web. build/web es lo que sirve en producción
# (pm2 kuratracker-web, puerto 3000) y build/web-demo lo que sirve la demo
# (pm2 kuratracker-web-demo, puerto 3001). Ninguno de los dos debe
# sobrescribirse como efecto secundario de un chequeo de calidad.
#
# Para reconstruir producción de verdad, usar scripts/build_prod.sh
# (requiere las credenciales reales de Supabase vía --dart-define).
#
# Uso:
#   ./scripts/build_gate.sh
#
# Salida: build/web-gate/ (ignorado por git; se puede borrar después).

set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> flutter analyze (criterio: 0 errores; warnings/info pre-existentes no bloquean)"
set +e
analyze_output=$(flutter analyze 2>&1)
analyze_exit=$?
set -e
echo "$analyze_output"
if echo "$analyze_output" | grep -qE "^\s*error •"; then
  echo "❌ flutter analyze encontró errores reales." >&2
  exit 1
fi
if [[ $analyze_exit -ne 0 ]]; then
  echo "(flutter analyze salió con código $analyze_exit por warnings/info, sin errores — continuando)"
fi

echo "==> flutter test"
flutter test

echo "==> flutter build web --release -o build/web-gate (SIN dart-define; salida desechable)"
flutter build web --release -o build/web-gate

echo ""
echo "✅ Build-gate OK. Salida en build/web-gate/ (NO se tocó build/web ni build/web-demo)."
echo "   Puedes borrar build/web-gate/ cuando termines: rm -rf build/web-gate"
