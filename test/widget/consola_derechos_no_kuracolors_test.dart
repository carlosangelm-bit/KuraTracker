import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prueba 9 (§6): NINGÚN archivo del chrome nuevo (consola "master · Derechos" y el
/// riel de navegación) menciona `KuraColors` — el alias legado, siempre morado; en un
/// hospital pinta mal. Todo color sale de `BrandTokens.of(context)`. Mismo patrón que
/// el escaneo de `_gatedScreens`.
///
/// Cubre `lib/features/platform/derechos/` (consola de derechos) y `lib/core/nav/`
/// (KuraNavRail: se usa igual en morado, azul y rosa). Un directorio puede no existir
/// todavía → no hay nada que revisar; cuando lleguen los archivos, un solo `KuraColors`
/// pone esto en ROJO.
void main() {
  const scanned = <String>[
    'lib/features/platform/derechos',
    'lib/core/nav',
  ];

  test('ningún archivo del chrome nuevo usa KuraColors', () {
    final offenders = <String>[];
    for (final path in scanned) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.readAsStringSync().contains('KuraColors')) offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'El chrome nuevo debe usar BrandTokens.of(context), no '
            'KuraColors (morado fijo). Infractores: $offenders');
  });
}
