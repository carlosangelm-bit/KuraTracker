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
    // `.horizon` con frontera de palabra: excluye `.horizontal` (Axis.horizontal).
    final memberAccess = RegExp(r'\.horizon\b');
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // El archivo del modelo declara el campo (`this.horizon`); no cuenta.
      if (f.path.endsWith('prevention_risk_engine.dart')) continue;
      if (memberAccess.hasMatch(f.readAsStringSync())) {
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
