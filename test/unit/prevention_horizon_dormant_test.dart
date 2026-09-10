import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fase 1.1 (horizontes de cuidado), aterrizaje DORMANTE. El campo `horizon` se
/// agrega al catálogo con valores PLACEHOLDER, pero NADA lo lee todavía para
/// agendar o mostrar: el comportamiento sigue derivándose de la cadencia. Estos
/// tests fijan esa promesa (decisión de Carlos, 8-sep) y validan el esquema sin
/// cablear runtime — cuando María clasifique de verdad, se cambia a propósito.
void main() {
  const validHorizons = {'ronda', 'puntual', 'seguimiento'};

  Map<String, dynamic> rules() => jsonDecode(
        File('assets/engine/prevention_rules.json').readAsStringSync(),
      ) as Map<String, dynamic>;

  // Recolecta todas las ACCIONES (objetos con id + label) del catálogo.
  List<Map<String, dynamic>> allActions(Object? node) {
    final out = <Map<String, dynamic>>[];
    void walk(Object? n) {
      if (n is Map) {
        if (n.containsKey('id') && n.containsKey('label')) {
          out.add(n.cast<String, dynamic>());
        }
        n.values.forEach(walk);
      } else if (n is List) {
        n.forEach(walk);
      }
    }

    walk(node);
    return out;
  }

  test('cada acción del catálogo trae un horizon válido', () {
    final actions = allActions(rules());
    expect(actions, isNotEmpty);
    for (final a in actions) {
      expect(a.containsKey('horizon'), isTrue,
          reason: 'La acción "${a['id']}" no tiene horizon.');
      expect(validHorizons, contains(a['horizon']),
          reason: 'horizon inválido en "${a['id']}": ${a['horizon']}');
    }
  });

  test('toda acción horizon==ronda tiene cadencia (invariante de 1.1)', () {
    final d = rules();
    final cadences = (d['cadences'] as Map).keys.toSet();
    for (final a in allActions(d)) {
      if (a['horizon'] == 'ronda') {
        expect(cadences, contains(a['id']),
            reason: 'La acción de ronda "${a['id']}" no tiene cadencia.');
      }
    }
  });

  test('NADA lee horizon todavía: ningún acceso .horizon en lib/', () {
    // Se excluye el PATRÓN, no el archivo (lección del guard de avatarInitial):
    // `this.horizon` es la DECLARACIÓN del campo (constructor del modelo) y se
    // permite; cualquier OTRO acceso de miembro `.horizon` es lectura y falla —
    // INCLUIDO el archivo del motor, que es justo donde vive schedulableActionsFor
    // y donde ocurriría el cableado. `\b` excluye `.horizontal`/`.horizonHours`;
    // el lookbehind `(?<!this)` excluye la declaración `this.horizon`.
    final read = RegExp(r'(?<!this)\.horizon\b');
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (read.hasMatch(f.readAsStringSync())) {
        offenders.add(f.path);
      }
    }
    // El modelo declara el campo (`this.horizon`, `horizon:`) pero NO hace acceso
    // de miembro `.horizon`; cuando alguien lo consuma para agendar/mostrar,
    // aparecerá aquí y este test obligará a revisar que los valores ya sean
    // clínicos (no placeholder) y a actualizar esta promesa.
    expect(offenders, isEmpty,
        reason: 'Algo ya lee .horizon (placeholder aún): $offenders');
  });
}
