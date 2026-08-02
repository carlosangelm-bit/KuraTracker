// Guardia anti "números mágicos" clínicos, Fase A del refactor data-driven.
//
// Tras externalizar los umbrales a assets/engine/clinical/*.json, la LÓGICA del
// motor y de los getters de KuraEngineInput NO debe contener literales numéricos
// clínicos: deben leerse de ClinicalParams. Este test extrae el código
// ejecutable (quita comentarios y el CONTENIDO de los strings — la prosa de las
// justificaciones sí puede mencionar números) y falla si aparece cualquiera de
// los umbrales clínicos como literal.
//
// Nota: las expresiones de interpolación (${...}) SÍ se conservan porque son
// código; por eso el umbral de etiqueta Braden (<=12) también se externalizó.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Valores clínicos que NO deben aparecer como literal en la lógica.
const _forbidden = <double>[
  15, // debridement_composition_min_pct
  30, // necrosis_extensa_min_pct
  12, // braden_alto_muy_alto_max
  17, // braden_a_cargo_clinica_max
  2, // infeccion_local_min_factores
  0.5, // depth_relleno_min_cm / abi_mod_min
  0.6, // banda compresión reducida
  0.8, // abi_high_min / banda precaución
  0.9, // banda fuerte
  1.4, // abi_incompresible_above
  3.0, // albumina_mild_min
  3.5, // albumina_normal_min
  7.0, // tunel_referencia_min_cm
];

const _files = <String>[
  'lib/engine/rules/kura_treatment_rules_engine.dart',
  'lib/engine/models/kura_engine_input.dart',
];

void main() {
  test('la lógica del motor no contiene números mágicos clínicos', () {
    final offenders = <String>[];
    for (final path in _files) {
      final src = File(path).readAsStringSync();
      var code = _stripStringsAndComments(src);
      // Quitar argumentos de formato (precisión), que no son clínicos.
      code = code.replaceAll(RegExp(r'toStringAsFixed\(\d+\)'), 'toStringAsFixed()');

      final numberRe = RegExp(r'(?<![\w.])\d+(?:\.\d+)?(?![\w])');
      for (final m in numberRe.allMatches(code)) {
        final value = double.parse(m.group(0)!);
        if (_forbidden.any((f) => (f - value).abs() < 1e-9)) {
          final ctx = code
              .substring((m.start - 25).clamp(0, code.length), m.end + 15)
              .replaceAll('\n', ' ')
              .trim();
          offenders.add('$path: literal "${m.group(0)}"  …$ctx…');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Umbrales clínicos hardcodeados en la lógica (deben leerse de '
          'ClinicalParams):\n${offenders.join('\n')}',
    );
  });
}

/// Devuelve el código con comentarios eliminados y el CONTENIDO textual de los
/// strings removido, PERO conservando las expresiones de interpolación `${...}`
/// (que son código). No hay strings raw ni triple-comilla en estos archivos.
String _stripStringsAndComments(String src) {
  final out = StringBuffer();
  final n = src.length;
  // Pila de comillas pendientes por cada interpolación abierta.
  final pendingQuote = <String>[];
  // Profundidad de llaves { } dentro de cada interpolación abierta.
  final interpBraceDepth = <int>[];
  String? quote; // comilla activa si estamos dentro de un string
  var i = 0;

  bool isWord(String ch) => RegExp(r'[A-Za-z0-9_]').hasMatch(ch);

  while (i < n) {
    final c = src[i];
    if (quote == null) {
      // --- modo código ---
      if (c == '/' && i + 1 < n && src[i + 1] == '/') {
        i += 2;
        while (i < n && src[i] != '\n') {
          i++;
        }
        continue;
      }
      if (c == '/' && i + 1 < n && src[i + 1] == '*') {
        i += 2;
        while (i + 1 < n && !(src[i] == '*' && src[i + 1] == '/')) {
          i++;
        }
        i += 2;
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        i++;
        continue;
      }
      if (c == '{' && interpBraceDepth.isNotEmpty) {
        interpBraceDepth[interpBraceDepth.length - 1]++;
        out.write(c);
        i++;
        continue;
      }
      if (c == '}' && interpBraceDepth.isNotEmpty) {
        if (interpBraceDepth.last == 0) {
          interpBraceDepth.removeLast();
          quote = pendingQuote.removeLast();
          i++;
          continue;
        }
        interpBraceDepth[interpBraceDepth.length - 1]--;
        out.write(c);
        i++;
        continue;
      }
      out.write(c);
      i++;
    } else {
      // --- modo string (contenido se descarta) ---
      if (c == r'\') {
        i += 2; // escape
        continue;
      }
      if (c == r'$' && i + 1 < n && src[i + 1] == '{') {
        pendingQuote.add(quote);
        interpBraceDepth.add(0);
        quote = null;
        i += 2;
        continue;
      }
      if (c == r'$' && i + 1 < n && isWord(src[i + 1])) {
        i += 2;
        while (i < n && isWord(src[i])) {
          i++;
        }
        continue;
      }
      if (c == quote) {
        quote = null;
        i++;
        continue;
      }
      i++; // descartar carácter de string
    }
  }
  return out.toString();
}
