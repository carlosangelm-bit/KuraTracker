// Reja que CIERRA la sección entera «Admin del centro»: ningún archivo bajo
// lib/features/admin/ debe usar KuraColors (el alias de marca FIJA que hacía salir estas
// pantallas moradas en un hospital) SALVO la deuda declarada abajo.
//
// _legacyPaletteDebt son las pantallas PROFUNDAS de /admin (las /admin/<x> avanzadas:
// protocolo-kura, productos-protocolo, acuity, escalas, recomendaciones, divulgaciones,
// depurar-expedientes), que están FUERA de este spec y quedan pendientes de su propia
// pasada a BrandTokens. Cada una con su cuenta EXACTA de usos.
//
// La prueba falla si:
//   1. Un archivo NO listado usa KuraColors — cubre las seis pantallas de sección
//      (Usuarios/Personal/Sitios/Configuración/Marca + el andamiaje) y cualquier sección
//      futura, sin nombrarlas una por una.
//   2. Un archivo listado tiene MÁS usos que los declarados — nadie agranda la deuda.
//   3. Un archivo listado tiene MENOS usos que los declarados — al convertir uno hay que
//      BAJAR su número, para que la lista se encoja de verdad y no se quede mintiendo.
//
// Local: es un escaneo de archivos (dart:io), no monta nada.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Deuda de paleta de las pantallas profundas de /admin, pendiente de una pasada propia.
const _legacyPaletteDebt = <String, int>{
  'protocol_product_rules_screen.dart': 17,
  'recommendations_reference_screen.dart': 8,
  'patient_cleanup_screen.dart': 8,
  'protocol_kura_screen.dart': 7,
  'data_disclosures_screen.dart': 3,
  'acuity_visit_type_map_screen.dart': 2,
  'acuity_session_type_screen.dart': 2,
  'scale_toggles_screen.dart': 1,
};

void main() {
  test('KuraColors bajo lib/features/admin/: cero salvo la deuda declarada', () {
    final dir = Directory('lib/features/admin');
    expect(dir.existsSync(), isTrue, reason: '¿ruta mal? no existe ${dir.path}');

    final offenders = <String>[];
    var scanned = 0;
    for (final e in dir.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      final name = e.uri.pathSegments.last;
      final actual = 'KuraColors'.allMatches(e.readAsStringSync()).length;
      final declared = _legacyPaletteDebt[name] ?? 0;
      if (actual == declared) continue;
      if (declared == 0) {
        offenders.add('$name: usa KuraColors ($actual) y no está en la deuda. '
            'Pásalo a BrandTokens.');
      } else if (actual > declared) {
        offenders.add('$name: creció la deuda de KuraColors ($declared → $actual). '
            'No agregues paleta vieja.');
      } else {
        offenders.add('$name: bajó a $actual usos de KuraColors (declarado '
            '$declared). Baja el número en _legacyPaletteDebt a $actual (o quítalo '
            'si llegó a 0) para que la lista encoja de verdad.');
      }
    }
    expect(scanned, greaterThan(10),
        reason: 'escaneó muy pocos archivos ($scanned); ¿ruta mal?');
    expect(offenders, isEmpty, reason: '\n${offenders.join('\n')}');
  });
}
