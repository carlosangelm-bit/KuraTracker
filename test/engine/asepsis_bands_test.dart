// Golden de ASEPSIS: los cinco cortes de banda (10/11, 20/21, 30/31, 40/41) →
// banda esperada, band_id estable y "¿se agenda la tarea de ISQ?".
//
// La interpretación (etiqueta + severidad) sale de scale_bands["ASEPSIS"] en
// thresholds.json — FUENTE ÚNICA del corte clínico. severity warn/danger ⇒ se
// agenda ISQ (misma condición que usa applyAsepsisTreatment). Un cambio de
// cualquier corte en el asset mueve a la vez la etiqueta y el disparo, y este
// golden lo detecta.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/params/clinical_params.dart';
import 'package:kuratracker/engine/risk/sum_scale.dart';

import 'clinical_params_fixture.dart';

SumScaleDef _asepsisDef() => SumScaleDef.fromJson(jsonDecode(
        File('assets/engine/scales/asepsis.json').readAsStringSync())
    as Map<String, dynamic>);

/// Condición idéntica a applyAsepsisTreatment: la banda ya es de infección.
bool _schedulesIsq(String? severity) =>
    severity == 'warn' || severity == 'danger';

void main() {
  setUpAll(loadClinicalParamsForTest);

  final def = _asepsisDef();

  // total, band_id, label, severity, ¿agenda ISQ?
  final cases = <(int, String, String, String, bool)>[
    (10, 'asepsis_satisfactoria', 'Cicatrización satisfactoria', 'ok', false),
    (11, 'asepsis_alteracion', 'Alteración de la cicatrización', 'watch', false),
    (20, 'asepsis_alteracion', 'Alteración de la cicatrización', 'watch', false),
    (21, 'asepsis_infeccion_menor', 'Infección menor', 'warn', true),
    (30, 'asepsis_infeccion_menor', 'Infección menor', 'warn', true),
    (31, 'asepsis_infeccion_moderada', 'Infección moderada', 'danger', true),
    (40, 'asepsis_infeccion_moderada', 'Infección moderada', 'danger', true),
    (41, 'asepsis_infeccion_severa', 'Infección severa', 'danger', true),
  ];

  for (final c in cases) {
    test('ASEPSIS ${c.$1} → ${c.$2} (ISQ=${c.$5})', () {
      final r = def.interpret(c.$1);
      expect(r.bandId, c.$2, reason: 'band_id en ${c.$1}');
      expect(r.label, c.$3, reason: 'label en ${c.$1}');
      expect(r.severity, c.$4, reason: 'severity en ${c.$1}');
      expect(_schedulesIsq(r.severity), c.$5, reason: 'ISQ en ${c.$1}');
    });
  }

  test('un total double (10.5) cae en una banda: no hay hueco entero/double', () {
    expect(def.interpret(10.5).bandId, 'asepsis_alteracion');
  });

  // --- Validación: ClinicalParams rechaza scale_bands mal formadas ---
  const validSource = {
    'protocolo': 'x',
    'rationale': 'x',
    'reviewed_by': 'x',
    'reviewed_date': '2026-08-27',
  };
  Map<String, dynamic> thresholdsWithAsepsis(Map<String, dynamic> node) {
    final t = jsonDecode(
            File('assets/engine/clinical/thresholds.json').readAsStringSync())
        as Map<String, dynamic>;
    (t['scale_bands'] as Map<String, dynamic>)['ASEPSIS'] = node;
    return t;
  }

  String arche() =>
      File('assets/engine/clinical/archetypes.json').readAsStringSync();

  void expectRejected(Map<String, dynamic> asepsisNode) {
    expect(
      () => ClinicalParams.fromJsonStrings(
        thresholdsJson: jsonEncode(thresholdsWithAsepsis(asepsisNode)),
        archetypesJson: arche(),
      ),
      throwsA(isA<ClinicalParamsException>()),
    );
  }

  test('rechaza scale_bands sin source', () {
    expectRejected({
      'domain': 'x',
      'bands': [
        {'band': 'a', 'from': null, 'to': null, 'to_inclusive': false, 'label': 'A'},
      ],
    });
  });

  test('rechaza scale_bands con hueco', () {
    expectRejected({
      'domain': 'x',
      'source': validSource,
      'bands': [
        {'band': 'a', 'from': null, 'from_inclusive': false, 'to': 10, 'to_inclusive': true, 'label': 'A'},
        {'band': 'b', 'from': 15, 'from_inclusive': false, 'to': null, 'to_inclusive': false, 'label': 'B'},
      ],
    });
  });

  test('rechaza scale_bands con frontera ambigua (traslape)', () {
    expectRejected({
      'domain': 'x',
      'source': validSource,
      'bands': [
        {'band': 'a', 'from': null, 'from_inclusive': false, 'to': 10, 'to_inclusive': true, 'label': 'A'},
        {'band': 'b', 'from': 10, 'from_inclusive': true, 'to': null, 'to_inclusive': false, 'label': 'B'},
      ],
    });
  });
}
