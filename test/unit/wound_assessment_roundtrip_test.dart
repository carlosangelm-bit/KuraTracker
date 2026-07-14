import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/models/wound.dart';

/// Prueba de round-trip: toJson() -> fromJson() debe preservar todos los
/// campos, en particular exudateType y lowAdherence (ambos gaps corregidos
/// en esta iteracion: exudateType no se parseaba en fromJson y no se
/// escribia en toJson; lowAdherence ya estaba correcto pero se cubre aqui
/// tambien como regresion).
void main() {
  group('WoundAssessment round-trip (toJson -> fromJson)', () {
    test('preserva exudateType y lowAdherence cuando estan presentes', () {
      final original = WoundAssessment(
        id: 'a1',
        consultationId: 'c1',
        woundId: 'w1',
        exudateType: ExudadoTipo.purulento,
        exudateAmount: ExudadoCantidad.moderado,
        infectionCriteria: const {InfeccionCriterioIwii.eritemaPerilesional},
        lowAdherence: true,
      );

      final roundTripped = WoundAssessment.fromJson(original.toJson());

      expect(roundTripped.exudateType, ExudadoTipo.purulento);
      expect(roundTripped.lowAdherence, true);
      expect(roundTripped.exudateAmount, ExudadoCantidad.moderado);
      expect(roundTripped.infectionCriteria, {InfeccionCriterioIwii.eritemaPerilesional});
    });

    test('exudateType null se preserva como null (no cae en "otro" por error)', () {
      final original = WoundAssessment(
        id: 'a2',
        consultationId: 'c2',
        woundId: 'w2',
        exudateType: null,
        lowAdherence: false,
      );

      final roundTripped = WoundAssessment.fromJson(original.toJson());

      expect(roundTripped.exudateType, isNull);
      expect(roundTripped.lowAdherence, false);
    });

    test('exudate_type desconocido/invalido cae a ExudadoTipo.otro sin lanzar', () {
      final json = <String, dynamic>{
        'id': 'a3',
        'consultation_id': 'c3',
        'wound_id': 'w3',
        'exudate_type': 'valor_no_reconocido',
      };

      final assessment = WoundAssessment.fromJson(json);

      expect(assessment.exudateType, ExudadoTipo.otro);
    });

    for (final tipo in ExudadoTipo.values) {
      test('exudateType.$tipo sobrevive el round-trip', () {
        final original = WoundAssessment(
          id: 'a-${tipo.name}',
          consultationId: 'c',
          woundId: 'w',
          exudateType: tipo,
        );
        final roundTripped = WoundAssessment.fromJson(original.toJson());
        expect(roundTripped.exudateType, tipo);
      });
    }
  });
}
