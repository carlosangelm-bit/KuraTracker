import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/module_key.dart';

/// Reja contra el hueco de gate por ruta huérfana. El redirect del router y el
/// nav gatean un módulo resolviendo la ruta con [ModuleKey.forRoute], que solo
/// atrapa la ruta del módulo y sus hijas (`m.route` y `m.route/...`). Una
/// pantalla de módulo colocada en una ruta de PRIMER NIVEL fuera de ese prefijo
/// queda sin gate: le pasó a `/admin` y a `/ekare-import`.
///
/// Este test recorre TODAS las rutas del router. Para las hijas (path relativo) NO
/// basta con que sean relativas: se resuelve su ruta COMPLETA contra el padre en el
/// árbol y se le aplica la MISMA regla que a una de primer nivel. Así una hija que
/// cuelga de un padre sin gate SÍ falla (ver el caso negativo abajo).
void main() {
  // Rutas que NO pertenecen a un módulo configurable y por eso forRoute devuelve
  // null a propósito: públicas/auth + dashboard; gateadas por ROL
  // (admin/platform/caregiver); y prevención hospitalaria (redirect propio).
  const ungated = <String>[
    '/login', '/demo', '/pago-', '/reset-password',
    '/admin', '/platform', '/caregiver',
    '/hospital', '/prevention-agenda',
  ];
  bool isUngatedOk(String p) =>
      p == '/' ||
      ungated.any((u) => p == u || p.startsWith('$u/') || p.startsWith(u));

  bool covered(String fullPath) =>
      ModuleKeyX.forRoute(fullPath) != null || isUngatedOk(fullPath);

  test('toda ruta (resuelta contra su padre) la cubre forRoute o la allowlist', () {
    final src = File('lib/core/router/app_router.dart').readAsStringSync();
    final paths = resolveFullPaths(src);
    expect(paths, isNotEmpty, reason: 'No se extrajo ninguna ruta del router.');
    // Sanidad: las hijas nuevas de /admin quedaron resueltas a ruta completa.
    expect(paths, contains('/admin/protocolo-kura'));

    for (final p in paths) {
      expect(
        covered(p),
        isTrue,
        reason: 'La ruta "$p" (ya resuelta a ruta completa) no la cubre '
            'ModuleKey.forRoute ni la allowlist. Si es la pantalla de un módulo, '
            'muévela BAJO la ruta del módulo para que herede el gate.',
      );
    }
  });

  test('caso negativo: una hija relativa colgada de un padre SIN gate falla', () {
    // /orphan-parent no es módulo ni allowlist → su hija resuelta tampoco.
    const synthetic = '''
      GoRoute(path: '/orphan-parent', builder: x, routes: [
        GoRoute(path: 'huerfana', builder: x),
      ]),
    ''';
    final paths = resolveFullPaths(synthetic);
    expect(paths, contains('/orphan-parent/huerfana'),
        reason: 'El resolvedor debe componer la ruta completa de la hija.');
    expect(covered('/orphan-parent/huerfana'), isFalse,
        reason: 'Una hija de un padre sin gate NO debe pasar como cubierta.');
    // Y con la regla vieja (relativa = siempre OK) esto habría pasado por error:
    expect('huerfana'.startsWith('/'), isFalse);
  });
}

/// Resuelve cada `path:` del router a su ruta COMPLETA, componiendo las hijas
/// relativas con el prefijo del padre (la nidificación se sigue por el bloque
/// `routes: [ … ]`). Los `path:` absolutos se devuelven tal cual (una hija absoluta
/// ignora al padre, como en go_router).
List<String> resolveFullPaths(String rawSrc) {
  final src = _stripComments(rawSrc);
  final out = <String>[];
  final parents = <String>['']; // pila de prefijos padre
  final popAt = <int>[]; // profundidad de corchetes a la que se hace pop
  var depth = 0;
  var lastPath = '';
  final pathRe = RegExp(r"path:\s*'([^']*)'");
  final routesRe = RegExp(r'routes:\s*\[');
  var i = 0;
  while (i < src.length) {
    final mp = pathRe.matchAsPrefix(src, i);
    if (mp != null) {
      final p = mp.group(1)!;
      out.add(_joinPath(parents.last, p));
      lastPath = p;
      i = mp.end;
      continue;
    }
    final mr = routesRe.matchAsPrefix(src, i);
    if (mr != null) {
      // El '[' del bloque routes abre un nivel: sus hijas cuelgan de lastPath.
      parents.add(_joinPath(parents.last, lastPath));
      popAt.add(depth + 1); // profundidad una vez consumido este '['
      lastPath = '';
      i = mr.end - 1; // dejar el '[' para el conteo normal
      continue;
    }
    final c = src[i];
    if (c == '[') {
      depth++;
    } else if (c == ']') {
      if (popAt.isNotEmpty && depth == popAt.last) {
        parents.removeLast();
        popAt.removeLast();
      }
      depth--;
    }
    i++;
  }
  return out;
}

String _joinPath(String parent, String p) {
  if (p.startsWith('/')) return p; // absoluta: ignora el padre
  if (parent.isEmpty || parent == '/') return '/$p';
  return '$parent/$p';
}

String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');
