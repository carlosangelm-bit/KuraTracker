// Tests de "deterioro objetivo" (kura_rules_v2, penalizacion de trayectoria
// del checkpoint/kura_sheehan_checkpoint). Compara consulta ACTUAL vs.
// INMEDIATAMENTE ANTERIOR (no basal).
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/engine/wound_deterioration_evaluator.dart';
import 'package:kuratracker/models/wound.dart';

WoundMeasurement _measurement({
  double areaCm2 = 10,
  double depthCm = 0.3,
  double granulationPct = 60,
  double sloughPct = 20,
  double necrosisPct = 0,
  double epithelializationPct = 20,
}) {
  return WoundMeasurement(
    id: 'm',
    woundId: 'w',
    measuredAt: DateTime(2026, 1, 1),
    lengthCm: 3,
    widthCm: 3,
    areaCm2: areaCm2,
    depthCm: depthCm,
    granulationPct: granulationPct,
    sloughPct: sloughPct,
    necrosisPct: necrosisPct,
    epithelializationPct: epithelializationPct,
  );
}

WoundAssessment _assessment({
  ExudadoCantidad exudateAmount = ExudadoCantidad.escaso,
  String? woundEdge = 'definido',
}) {
  return WoundAssessment(
    id: 'a',
    consultationId: 'c',
    woundId: 'w',
    exudateAmount: exudateAmount,
    woundEdge: woundEdge,
  );
}

void main() {
  group('WoundDeteriorationEvaluator: deterioroDelLecho', () {
    test('sin cambios relevantes => sin deterioro', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(),
        previous: _measurement(),
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isFalse);
      expect(result.motivos, isEmpty);
    });

    test('tejido desvitalizado (necrosis+esfacelo) aumenta >10 puntos => deterioro', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(sloughPct: 40, necrosisPct: 10), // 50
        previous: _measurement(sloughPct: 20, necrosisPct: 0), // 20 -> +30
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isTrue);
      expect(result.motivos.any((m) => m.contains('Tejido desvitalizado')), isTrue);
    });

    test('tejido desvitalizado aumenta exactamente 10 puntos => NO deterioro (umbral estricto >10)', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(sloughPct: 30, necrosisPct: 0), // 30
        previous: _measurement(sloughPct: 20, necrosisPct: 0), // 20 -> +10 exacto
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isFalse);
    });

    test('granulacion disminuye >=10 puntos => deterioro', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(granulationPct: 40),
        previous: _measurement(granulationPct: 60), // -20
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isTrue);
      expect(result.motivos.any((m) => m.contains('Granulacion')), isTrue);
    });

    test('granulacion disminuye exactamente 10 puntos => SI deterioro (umbral inclusivo >=10)', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(granulationPct: 50),
        previous: _measurement(granulationPct: 60), // -10 exacto
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isTrue);
    });

    test('area aumenta >10% => deterioro', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(areaCm2: 12), // +20% vs 10
        previous: _measurement(areaCm2: 10),
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isTrue);
      expect(result.motivos.any((m) => m.contains('Area aumento')), isTrue);
    });

    test('area aumenta exactamente 10% => NO deterioro (umbral estricto >10%)', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(areaCm2: 11), // +10% exacto vs 10
        previous: _measurement(areaCm2: 10),
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isFalse);
    });

    test('desaparicion de epitelio (>0 -> 0) => deterioro', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(epithelializationPct: 0),
        previous: _measurement(epithelializationPct: 15),
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isTrue);
      expect(result.motivos.any((m) => m.contains('epitelio')), isTrue);
    });

    test('profundidad aumenta >0.5cm => deterioro', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(depthCm: 1.0),
        previous: _measurement(depthCm: 0.4), // +0.6
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isTrue);
      expect(result.motivos.any((m) => m.contains('Profundidad')), isTrue);
    });

    test('profundidad aumenta exactamente 0.5cm => NO deterioro (umbral estricto >0.5)', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(depthCm: 0.9),
        previous: _measurement(depthCm: 0.4), // +0.5 exacto
        currentAssessment: _assessment(),
        previousAssessment: _assessment(),
      );
      expect(result.deterioroDelLecho, isFalse);
    });

    test('bordes macerado/epibole de nueva aparicion => deterioro', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(),
        previous: _measurement(),
        currentAssessment: _assessment(woundEdge: 'macerado'),
        previousAssessment: _assessment(woundEdge: 'definido'),
      );
      expect(result.deterioroDelLecho, isTrue);
      expect(result.motivos.any((m) => m.contains('Bordes evertidos')), isTrue);
    });

    test('borde epibole que ya estaba presente antes NO cuenta como nuevo deterioro', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(),
        previous: _measurement(),
        currentAssessment: _assessment(woundEdge: 'epibole'),
        previousAssessment: _assessment(woundEdge: 'epibole'),
      );
      expect(result.deterioroDelLecho, isFalse);
    });
  });

  group('WoundDeteriorationEvaluator: aumentoDeExudado (mala evolucion)', () {
    test('exudado sube >=1 nivel vs. visita previa => aumentoDeExudado true', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(),
        previous: _measurement(),
        currentAssessment: _assessment(exudateAmount: ExudadoCantidad.moderado),
        previousAssessment: _assessment(exudateAmount: ExudadoCantidad.escaso),
      );
      expect(result.aumentoDeExudado, isTrue);
      expect(result.motivos.any((m) => m.contains('Exudado aumento')), isTrue);
    });

    test('exudado sube 2 niveles (ninguno -> moderado) tambien cuenta', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(),
        previous: _measurement(),
        currentAssessment: _assessment(exudateAmount: ExudadoCantidad.moderado),
        previousAssessment: _assessment(exudateAmount: ExudadoCantidad.ninguno),
      );
      expect(result.aumentoDeExudado, isTrue);
    });

    test('exudado se mantiene igual => aumentoDeExudado false', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(),
        previous: _measurement(),
        currentAssessment: _assessment(exudateAmount: ExudadoCantidad.escaso),
        previousAssessment: _assessment(exudateAmount: ExudadoCantidad.escaso),
      );
      expect(result.aumentoDeExudado, isFalse);
    });

    test('exudado disminuye => aumentoDeExudado false (mejora, no mala evolucion)', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(),
        previous: _measurement(),
        currentAssessment: _assessment(exudateAmount: ExudadoCantidad.escaso),
        previousAssessment: _assessment(exudateAmount: ExudadoCantidad.abundante),
      );
      expect(result.aumentoDeExudado, isFalse);
    });

    test('sin evaluaciones (null) => aumentoDeExudado false, sin inventar datos', () {
      final result = WoundDeteriorationEvaluator.evaluate(
        current: _measurement(),
        previous: _measurement(),
      );
      expect(result.aumentoDeExudado, isFalse);
      expect(result.deterioroDelLecho, isFalse);
    });
  });
}
