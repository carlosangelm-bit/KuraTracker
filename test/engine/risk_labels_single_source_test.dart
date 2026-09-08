// Guardia de FUENTE ÚNICA para las etiquetas de banda de Braden (Fase A del
// re-bandeo). El bug que motivó esto NO fue un número: fue RE-DERIVAR la etiqueta
// ("riesgo muy alto" que nunca se imprimía). El guard numérico no sirve para
// esto (choca con enteros de layout como fontSize:12); la medicina correcta es
// un guard de PATRÓN sobre las etiquetas, igual que el de avatarInitial.
//
// Regla: ningún archivo de lib/ fuera de la FUENTE ÚNICA (braden_scale.json, que
// lee braden_scale.dart) puede contener una etiqueta de banda de Braden como
// literal exacto. Las etiquetas se leen del propio asset, así que el guard se
// adapta solo cuando la Fase C renombra 'medio'→'moderado' o agrega 'sin riesgo'.
//
// Exclusión ÚNICA y documentada: prevention_risk_engine.dart define el enum
// RiskLevel, una escala DISTINTA (estratificación de prevención) que comparte los
// strings "Riesgo alto/medio/bajo" por coincidencia del vocabulario de riesgo, no
// por re-derivar Braden. No es una lista que crezca: es el dueño de otra escala.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/params/clinical_params.dart';
import 'package:kuratracker/engine/risk/prevention_risk_engine.dart';

const _singleSource = 'lib/engine/risk/braden_scale.dart';
const _otherScaleOwner = 'lib/engine/risk/prevention_risk_engine.dart';

/// Quita comentarios (// y /* */) CONSERVANDO los literales de string, para no
/// marcar una etiqueta citada en un comentario como si fuera código.
String _stripComments(String src) {
  final out = StringBuffer();
  final n = src.length;
  String? quote;
  var i = 0;
  while (i < n) {
    final c = src[i];
    if (quote != null) {
      out.write(c);
      if (c == r'\' && i + 1 < n) {
        out.write(src[i + 1]);
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      out.write(c);
      i++;
      continue;
    }
    if (c == '/' && i + 1 < n && src[i + 1] == '/') {
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
    out.write(c);
    i++;
  }
  return out.toString();
}

Set<String> _bradenLabels() {
  final j = jsonDecode(File('assets/engine/braden_scale.json').readAsStringSync())
      as Map<String, dynamic>;
  return ((j['risk_levels'] as List).cast<Map<String, dynamic>>())
      .map((b) => (b['label'] as String).trim().toLowerCase())
      .toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ninguna etiqueta de banda de Braden se re-deriva fuera de la fuente única', () {
    final labels = _bradenLabels();
    expect(labels, isNotEmpty);
    // Literales de string simples/dobles (sin interpolación compleja); basta para
    // detectar una etiqueta hardcodeada.
    final strRe = RegExp(r"""(['"])((?:\\.|(?!\1).)*)\1""");
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == _singleSource || path == _otherScaleOwner) continue;
      final src = _stripComments(entity.readAsStringSync());
      for (final m in strRe.allMatches(src)) {
        final content = m.group(2)!.trim().toLowerCase();
        if (labels.contains(content)) {
          offenders.add('$path: "${m.group(2)}"');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Etiquetas de banda de Braden hardcodeadas (deben leerse de '
          'BradenScale.bandFor / braden_scale.json):\n${offenders.join('\n')}',
    );
  });

  test('RiskLevel.sinRiesgo.label DUPLICA la etiqueta de la banda sin_riesgo A PROPÓSITO', () {
    // bradenBandLevel mapea la banda de Braden al enum RiskLevel, así que la
    // etiqueta del enum ('Sin riesgo') COINCIDE con la de la banda sin_riesgo del
    // JSON. El literal vive en prevention_risk_engine.dart, EXCLUIDO del guard de
    // etiquetas — por eso hace falta este pin: si alguien renombra la banda en el
    // JSON, el enum no la sigue solo, y este test obliga a decidir aquí.
    final j = jsonDecode(File('assets/engine/braden_scale.json').readAsStringSync())
        as Map<String, dynamic>;
    final band = (j['risk_levels'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((b) => b['id'] == 'sin_riesgo');
    expect(RiskLevel.sinRiesgo.label, band['label'],
        reason: 'Son iguales a propósito. Si cambia la etiqueta de la banda '
            'sin_riesgo en braden_scale.json, decide si RiskLevel.sinRiesgo debe '
            'seguirla (lo usan el tablero y las tarjetas de paciente).');
  });

  test('la prosa de scale_applicability.json (braden_riesgo/braden_bajo) sigue en sincronía con ClinicalParams',
      () async {
    ClinicalParams.register(await ClinicalParams.loadFromAssets());
    final params = ClinicalParams.I;
    final j =
        jsonDecode(await rootBundle.loadString('assets/engine/scale_applicability.json'))
            as Map<String, dynamic>;
    final labels = (j['factor_labels'] as Map).cast<String, dynamic>();

    // Cada etiqueta menciona un número; ese número debe ser el del param, o el
    // texto que ve el clínico se desincroniza en el primer cambio de umbral.
    int numIn(String s) =>
        int.parse(RegExp(r'\d+').firstMatch(s)!.group(0)!);
    expect(numIn(labels['braden_riesgo'] as String), params.bradenEnRiesgoMax,
        reason: 'braden_riesgo (prosa) no coincide con braden_en_riesgo_max');
    expect(numIn(labels['braden_bajo'] as String), params.bradenAltoMuyAltoMax,
        reason: 'braden_bajo (prosa) no coincide con braden_alto_muy_alto_max');
  });
}
