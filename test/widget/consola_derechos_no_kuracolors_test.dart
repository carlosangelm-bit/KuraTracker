import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prueba 9 (§6): NINGÚN archivo de la consola "master · Derechos" menciona
/// `KuraColors` — el alias legado, siempre morado; en un hospital pinta mal. Todo
/// color sale de `BrandTokens.of(context)`. Mismo patrón que el escaneo de
/// `_gatedScreens`.
///
/// La consola vive en `lib/features/platform/derechos/`. En la ETAPA 1 (base, sin
/// UI) el directorio puede no existir todavía: entonces no hay nada que revisar y
/// la prueba pasa. Cuando lleguen las pantallas (etapas 2+), un solo `KuraColors`
/// en cualquiera pone esto en ROJO.
void main() {
  test('ningún archivo de la consola master · Derechos usa KuraColors', () {
    final dir = Directory('lib/features/platform/derechos');
    if (!dir.existsSync()) return; // etapa 1: aún no hay pantallas de la consola

    final offenders = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.readAsStringSync().contains('KuraColors')) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'La consola master debe usar BrandTokens.of(context), no '
            'KuraColors (morado fijo). Infractores: $offenders');
  });
}
