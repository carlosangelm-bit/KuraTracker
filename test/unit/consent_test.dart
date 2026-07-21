// Tests del modelo Consent (consentimientos digitales) y su serialización.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/consent.dart';

void main() {
  group('ConsentType', () {
    test('dbValue/fromDb roundtrip', () {
      for (final t in ConsentType.values) {
        expect(ConsentTypeLabel.fromDb(t.dbValue), t);
      }
    });

    test('los 3 tipos del protocolo están presentes', () {
      expect(ConsentType.values.map((t) => t.dbValue).toSet(),
          {'privacidad', 'fotografia', 'desbridamiento'});
    });

    test('fromDb desconocido devuelve null', () {
      expect(ConsentTypeLabel.fromDb('otro'), isNull);
    });
  });

  group('Consent serialización', () {
    test('roundtrip toJson/fromJson', () {
      final c = Consent(
        id: 'c1',
        patientId: 'p1',
        type: ConsentType.fotografia,
        granted: true,
        grantedAt: DateTime(2026, 7, 20, 9, 0),
        signedBy: 'Paciente',
        docRef: 'folio-123',
        createdAt: DateTime(2026, 7, 20, 9, 0),
      );
      final back = Consent.fromJson(c.toJson());
      expect(back.id, c.id);
      expect(back.patientId, c.patientId);
      expect(back.type, c.type);
      expect(back.granted, isTrue);
      expect(back.grantedAt, c.grantedAt);
      expect(back.signedBy, 'Paciente');
      expect(back.docRef, 'folio-123');
    });

    test('granted por defecto false y granted_at null cuando no otorgado', () {
      final c = Consent.fromJson({
        'id': 'c2',
        'patient_id': 'p2',
        'type': 'privacidad',
        'granted': false,
        'granted_at': null,
        'signed_by': null,
        'doc_ref': null,
        'created_at': DateTime(2026, 7, 20).toIso8601String(),
      });
      expect(c.granted, isFalse);
      expect(c.grantedAt, isNull);
      expect(c.type, ConsentType.privacidad);
    });
  });
}
