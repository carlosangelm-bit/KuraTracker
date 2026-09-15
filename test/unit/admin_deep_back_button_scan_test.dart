// §13.1 — Cada hija PROFUNDA de /admin trae un KuraBackButton con fallback a Configuración
// (su punto de entrada). El test de INVOCACIÓN sobre el router (montar cada pantalla y tocar
// la flecha) resultó inviable: dos de ellas —las de Acuity— disparan una petición de red en
// initState, que deja un Timer pendiente y hace fallar el widget test al desmontar. Tal como
// pide el §13.1 para ese caso, se SUSTITUYE por una reja de FUENTE con la lista EXACTA y
// enumerada de las ocho (como la reja de KuraColors): lee los .dart, no monta nada → local y
// determinista. Una novena pantalla profunda se añade AQUÍ el día que se declare.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Las OCHO hijas profundas de /admin (app_router.dart, fuera del shell de secciones).
const _deepScreens = <String>[
  'lib/features/admin/protocol_kura_screen.dart',
  'lib/features/admin/protocol_product_rules_screen.dart',
  'lib/features/admin/acuity_session_type_screen.dart',
  'lib/features/admin/acuity_visit_type_map_screen.dart',
  'lib/features/admin/patient_cleanup_screen.dart',
  'lib/features/admin/scale_toggles_screen.dart',
  'lib/features/admin/recommendations_reference_screen.dart',
  'lib/features/admin/data_disclosures_screen.dart',
];

void main() {
  test('las ocho hijas profundas de /admin traen KuraBackButton → Configuración', () {
    final missing = <String>[];
    for (final path in _deepScreens) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: 'no existe $path');
      final src = f.readAsStringSync();
      final ok = src.contains('KuraBackButton') &&
          src.contains("fallback: '/admin/configuracion'");
      if (!ok) missing.add(path);
    }
    expect(missing, isEmpty,
        reason: 'sin salida (KuraBackButton con fallback a Configuración):\n'
            '${missing.join('\n')}');
  });

  // Guarda de enumeración: si aparece una novena hija profunda de /admin en el router (una
  // GoRoute '/admin/…' que no sea de las seis secciones ni las de arriba), hay que
  // añadirla a _deepScreens. Se detecta contando las rutas profundas en app_router.
  test('no hay una novena hija profunda de /admin sin cubrir', () {
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    const sections = {
      'usuarios', 'personal', 'sitios', 'configuracion', 'marca', 'licencias'
    };
    // Rutas absolutas '/admin/<x>' declaradas en el router.
    final paths = RegExp(r"path:\s*'(/admin/[a-z0-9-]+)'")
        .allMatches(router)
        .map((m) => m.group(1)!)
        .where((p) => !sections.contains(p.split('/').last))
        .toSet();
    expect(paths.length, _deepScreens.length,
        reason: 'el router declara ${paths.length} hijas profundas de /admin '
            '(${paths.toList()..sort()}) pero _deepScreens lista '
            '${_deepScreens.length}. Añade la nueva a la reja.');
  });
}
