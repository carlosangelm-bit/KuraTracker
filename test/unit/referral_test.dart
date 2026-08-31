// Tests del modelo Referral (formato de referencia/interconsulta, Prompt 6).
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/referral.dart';

void main() {
  group('ReferralStatus / ReferralAdjunto', () {
    test('status dbValue/fromDb roundtrip', () {
      for (final s in ReferralStatus.values) {
        expect(ReferralStatusLabel.fromDb(s.dbValue), s);
      }
    });

    test('adjunto jsonKey/fromKey roundtrip y las claves del checklist', () {
      for (final a in ReferralAdjunto.values) {
        expect(ReferralAdjuntoLabel.fromKey(a.jsonKey), a);
      }
      expect(
        ReferralAdjunto.values.map((a) => a.jsonKey).toSet(),
        {
          'reporte_ekare',
          'resumen_clinico',
          'cultivo',
          'itb',
          'laboratorios',
          'estudios_gabinete',
          'informes_previos_especialidades',
        },
      );
    });
  });

  group('Referral serialización', () {
    test('adjuntosJson incluye todas las claves canónicas con booleanos', () {
      final r = Referral(
        id: 'r1',
        patientId: 'p1',
        especialidad: 'Angiología',
        motivo: 'ITB anómalo',
        adjuntos: {ReferralAdjunto.itb, ReferralAdjunto.reporteEkare},
        createdAt: DateTime(2026, 7, 20),
      );
      expect(r.adjuntosJson(), {
        'reporte_ekare': true,
        'resumen_clinico': false,
        'cultivo': false,
        'itb': true,
        'laboratorios': false,
        'estudios_gabinete': false,
        'informes_previos_especialidades': false,
      });
    });

    test('roundtrip toJson/fromJson conserva datos y estado de respuesta', () {
      final r = Referral(
        id: 'r9',
        patientId: 'p9',
        woundId: 'w9',
        consultationId: 'c9',
        staffId: 's9',
        especialidad: 'Infectología',
        motivo: 'Infección propagada',
        adjuntos: {ReferralAdjunto.cultivo, ReferralAdjunto.laboratorios},
        status: ReferralStatus.respondida,
        referralSignedBy: 'Dra. X',
        referralSignedLicense: '12345',
        returnDocRef: 'folio-77',
        returnNotes: 'Iniciar antibiótico IV',
        returnedAt: DateTime(2026, 7, 22, 10),
        createdAt: DateTime(2026, 7, 20),
      );
      final back = Referral.fromJson(r.toJson());
      expect(back.especialidad, 'Infectología');
      expect(back.adjuntos,
          {ReferralAdjunto.cultivo, ReferralAdjunto.laboratorios});
      expect(back.status, ReferralStatus.respondida);
      expect(back.isRespondida, isTrue);
      expect(back.returnDocRef, 'folio-77');
      expect(back.returnNotes, 'Iniciar antibiótico IV');
      expect(back.returnedAt, DateTime(2026, 7, 22, 10));
      expect(back.referralSignedLicense, '12345');
    });

    test('referencia nueva (sin respuesta) -> isRespondida false, enviada', () {
      final r = Referral.fromJson({
        'id': 'r2',
        'patient_id': 'p2',
        'especialidad': 'Cirugía',
        'motivo': 'Túnel profundo',
        'status': 'enviada',
        'created_at': DateTime(2026, 7, 20).toIso8601String(),
      });
      expect(r.isRespondida, isFalse);
      expect(r.status, ReferralStatus.enviada);
      expect(r.adjuntos, isEmpty);
    });
  });
}
