// Tests del modelo ClinicalAmendment (notas de enmienda, Fase 4).
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/clinical_amendment.dart';

void main() {
  group('ClinicalAmendment', () {
    test('roundtrip toJson/fromJson', () {
      final a = ClinicalAmendment(
        id: 'a1',
        patientId: 'p1',
        consultationId: 'c1',
        body: 'Se corrige el tamaño de la herida a 3x2 cm.',
        reason: 'Error de captura',
        staffId: 's1',
        signedBy: 'Dra. X',
        signedLicense: '12345',
        createdAt: DateTime(2026, 7, 21, 11, 0),
      );
      final back = ClinicalAmendment.fromJson(a.toJson());
      expect(back.id, 'a1');
      expect(back.patientId, 'p1');
      expect(back.consultationId, 'c1');
      expect(back.body, 'Se corrige el tamaño de la herida a 3x2 cm.');
      expect(back.reason, 'Error de captura');
      expect(back.signedBy, 'Dra. X');
      expect(back.signedLicense, '12345');
      expect(back.createdAt, DateTime(2026, 7, 21, 11, 0));
    });

    test('campos opcionales ausentes -> null', () {
      final a = ClinicalAmendment.fromJson({
        'id': 'a2',
        'patient_id': 'p2',
        'body': 'Aclaración sin firma resuelta.',
        'created_at': DateTime(2026, 7, 21).toIso8601String(),
      });
      expect(a.consultationId, isNull);
      expect(a.reason, isNull);
      expect(a.signedBy, isNull);
    });
  });
}
