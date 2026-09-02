import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/module_key.dart';

/// Reja contra el hueco de gate por ruta huérfana. El redirect del router y el
/// nav gatean un módulo resolviendo la ruta con [ModuleKey.forRoute], que solo
/// atrapa la ruta del módulo y sus hijas (`m.route` y `m.route/...`). Una
/// pantalla de módulo colocada en una ruta de PRIMER NIVEL fuera de ese prefijo
/// queda sin gate: le pasó a `/admin` y a `/ekare-import` (este último abría el
/// importador de eKare desde cualquier centro, violando la regla de producto).
///
/// Este test recorre TODAS las rutas del router y exige que cada una la cubra
/// forRoute (pertenece a un módulo) o esté en la allowlist de rutas que
/// legítimamente NO son de módulo (públicas/auth, gateadas por rol, o por la
/// lógica especial de prevención). Si mañana alguien agrega la pantalla de un
/// módulo en una ruta huérfana, este test se pone rojo antes del deploy.
void main() {
  test('toda ruta del router la cubre forRoute o está en la allowlist no-módulo',
      () {
    final src = File('lib/core/router/app_router.dart').readAsStringSync();
    final paths = RegExp(r"path:\s*'([^']*)'")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toList();
    expect(paths, isNotEmpty,
        reason: 'No se extrajo ninguna ruta del router.');

    // Rutas que NO pertenecen a un módulo configurable y por eso forRoute
    // devuelve null a propósito: públicas/auth + dashboard; gateadas por ROL
    // (admin/platform/caregiver); y las de prevención hospitalaria que el
    // redirect gatea con lógica propia (needsPrevention), no por forRoute.
    const ungated = <String>[
      '/login', '/demo', '/pago-', '/reset-password',
      '/admin', '/platform', '/caregiver',
      '/hospital', '/prevention-agenda',
    ];
    bool isUngatedOk(String p) =>
        p == '/' || ungated.any((u) => p == u || p.startsWith('$u/') || p.startsWith(u));

    for (final p in paths) {
      final covered = ModuleKeyX.forRoute(p) != null;
      expect(
        covered || isUngatedOk(p),
        isTrue,
        reason: 'La ruta "$p" no la cubre ModuleKey.forRoute ni está en la '
            'allowlist de rutas no-módulo. Si es la pantalla de un módulo, '
            'muévela BAJO la ruta del módulo (p.ej. /import-export/...) para que '
            'herede el gate; es el hueco que tuvieron /admin y /ekare-import.',
      );
    }
  });
}
