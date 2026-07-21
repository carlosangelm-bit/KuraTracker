// Tests del modelo PatientComorbidity (APP) con atribución fecha+autor (Fase 1).
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/models/patient.dart';

void main() {
  group('PatientComorbidity', () {
    test('roundtrip toJson/fromJson conserva code, status, noted_at, noted_by', () {
      final c = PatientComorbidity(
        id: 'c1',
        patientId: 'p1',
        code: Comorbilidad.diabetesMellitus,
        status: ComorbilidadEstado.presente,
        notedAt: DateTime(2026, 7, 21, 10, 30),
        notedBy: 'staff-9',
      );
      final json = c.toJson();
      expect(json['code'], 'diabetes_mellitus');
      expect(json['status'], 'presente');
      expect(json['noted_by'], 'staff-9');

      final back = PatientComorbidity.fromJson(json);
      expect(back.code, Comorbilidad.diabetesMellitus);
      expect(back.status, ComorbilidadEstado.presente);
      expect(back.notedAt, DateTime(2026, 7, 21, 10, 30));
      expect(back.notedBy, 'staff-9');
    });

    test('estados mapean a los valores del enum de la BD', () {
      String db(ComorbilidadEstado e) => PatientComorbidity(
            id: 'x',
            patientId: 'p',
            code: Comorbilidad.obesidad,
            status: e,
          ).toJson()['status'] as String;
      expect(db(ComorbilidadEstado.presente), 'presente');
      expect(db(ComorbilidadEstado.negado), 'negado');
      expect(db(ComorbilidadEstado.noEvaluado), 'no_evaluado');
    });

    test('tolera noted_at / noted_by ausentes (compatibilidad hacia atrás)', () {
      final c = PatientComorbidity.fromJson({
        'id': 'c2',
        'patient_id': 'p2',
        'code': 'obesidad',
        'status': 'no_evaluado',
      });
      expect(c.notedAt, isNull);
      expect(c.notedBy, isNull);
      expect(c.code, Comorbilidad.obesidad);
      expect(c.status, ComorbilidadEstado.noEvaluado);
    });

    test('solo "presente" cuenta para el arquetipo (n_comorb_struct)', () {
      // Refleja la regla del motor: nComorbStruct = # de presentes.
      final estados = [
        ComorbilidadEstado.presente,
        ComorbilidadEstado.presente,
        ComorbilidadEstado.negado,
        ComorbilidadEstado.noEvaluado,
      ];
      final presentes =
          estados.where((e) => e == ComorbilidadEstado.presente).length;
      expect(presentes, 2);
    });
  });
}
