// Tests del modelo AdverseEvent (módulo de eventos adversos / COFEPRIS):
// clasificación por gravedad, checklist de señales de alarma, serialización y
// la regla de reporte ≤24 h de los eventos centinela.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/adverse_event.dart';

AdverseEvent _event({
  AdverseEventSeverity severity = AdverseEventSeverity.leve,
  DateTime? occurredAt,
  DateTime? reportedAt,
  Set<AdverseEventAlarmSign> alarmSigns = const {},
}) {
  return AdverseEvent(
    id: 'e1',
    organizationId: 'org1',
    patientId: 'p1',
    occurredAt: occurredAt ?? DateTime(2026, 7, 20, 10, 0),
    type: 'Infección',
    severity: severity,
    alarmSigns: alarmSigns,
    reportedAt: reportedAt,
    createdAt: DateTime(2026, 7, 20, 10, 5),
  );
}

void main() {
  group('Gravedad', () {
    test('dbValue/fromDb roundtrip para todos los valores', () {
      for (final s in AdverseEventSeverity.values) {
        expect(AdverseEventSeverityLabel.fromDb(s.dbValue), s);
      }
    });

    test('fromDb con valor desconocido cae a leve (no lanza)', () {
      expect(AdverseEventSeverityLabel.fromDb('inexistente'),
          AdverseEventSeverity.leve);
    });
  });

  group('Señales de alarma', () {
    test('jsonKey/fromKey roundtrip', () {
      for (final s in AdverseEventAlarmSign.values) {
        expect(AdverseEventAlarmSignLabel.fromKey(s.jsonKey), s);
      }
    });

    test('fromKey desconocida devuelve null', () {
      expect(AdverseEventAlarmSignLabel.fromKey('nope'), isNull);
    });

    test('las 4 señales del protocolo están presentes', () {
      expect(AdverseEventAlarmSign.values, hasLength(4));
      expect(
        AdverseEventAlarmSign.values.map((e) => e.jsonKey).toSet(),
        {'fiebre_38', 'sangrado_10min', 'linfangitis', 'signos_sistemicos'},
      );
    });
  });

  group('Regla de reporte ≤24 h (centinela)', () {
    test('centinela sin reportar => needsReport true', () {
      expect(_event(severity: AdverseEventSeverity.centinela).needsReport, isTrue);
    });

    test('centinela ya reportado => needsReport false', () {
      final e = _event(
        severity: AdverseEventSeverity.centinela,
        reportedAt: DateTime(2026, 7, 20, 12, 0),
      );
      expect(e.needsReport, isFalse);
      expect(e.isReported, isTrue);
    });

    test('gravedad no centinela nunca requiere reporte', () {
      for (final s in [
        AdverseEventSeverity.leve,
        AdverseEventSeverity.moderado,
        AdverseEventSeverity.grave,
      ]) {
        expect(_event(severity: s).needsReport, isFalse, reason: '$s');
      }
    });

    test('reportDeadline = occurredAt + 24 h', () {
      final e = _event(
        severity: AdverseEventSeverity.centinela,
        occurredAt: DateTime(2026, 7, 20, 10, 0),
      );
      expect(e.reportDeadline, DateTime(2026, 7, 21, 10, 0));
    });

    test('isReportOverdue: vencido solo si pendiente y now > deadline', () {
      final e = _event(
        severity: AdverseEventSeverity.centinela,
        occurredAt: DateTime(2026, 7, 20, 10, 0),
      );
      // Antes del vencimiento.
      expect(e.isReportOverdue(DateTime(2026, 7, 21, 9, 59)), isFalse);
      // Después del vencimiento.
      expect(e.isReportOverdue(DateTime(2026, 7, 21, 10, 1)), isTrue);
    });

    test('un centinela reportado no está vencido aunque pase el plazo', () {
      final e = _event(
        severity: AdverseEventSeverity.centinela,
        occurredAt: DateTime(2026, 7, 20, 10, 0),
        reportedAt: DateTime(2026, 7, 20, 12, 0),
      );
      expect(e.isReportOverdue(DateTime(2026, 7, 25, 10, 0)), isFalse);
    });
  });

  group('Serialización', () {
    test('alarmSignsJson incluye TODAS las claves canónicas con booleanos', () {
      final e = _event(alarmSigns: {
        AdverseEventAlarmSign.fiebre38,
        AdverseEventAlarmSign.linfangitis,
      });
      final json = e.alarmSignsJson();
      expect(json, {
        'fiebre_38': true,
        'sangrado_10min': false,
        'linfangitis': true,
        'signos_sistemicos': false,
      });
    });

    test('roundtrip toJson/fromJson conserva los datos', () {
      final original = AdverseEvent(
        id: 'e9',
        organizationId: 'org9',
        patientId: 'p9',
        woundId: 'w9',
        consultationId: 'c9',
        staffId: 's9',
        occurredAt: DateTime(2026, 7, 20, 8, 30),
        type: 'Dehiscencia',
        severity: AdverseEventSeverity.grave,
        alarmSigns: {
          AdverseEventAlarmSign.sangrado10min,
          AdverseEventAlarmSign.signosSistemicos,
        },
        description: 'desc',
        actionsTaken: 'acciones',
        evolution: 'evolución',
        reportedAt: DateTime(2026, 7, 20, 9, 0),
        createdAt: DateTime(2026, 7, 20, 8, 45),
      );
      final back = AdverseEvent.fromJson(original.toJson());

      expect(back.id, original.id);
      expect(back.organizationId, original.organizationId);
      expect(back.patientId, original.patientId);
      expect(back.woundId, original.woundId);
      expect(back.consultationId, original.consultationId);
      expect(back.staffId, original.staffId);
      expect(back.occurredAt, original.occurredAt);
      expect(back.type, original.type);
      expect(back.severity, original.severity);
      expect(back.alarmSigns, original.alarmSigns);
      expect(back.description, original.description);
      expect(back.actionsTaken, original.actionsTaken);
      expect(back.evolution, original.evolution);
      expect(back.reportedAt, original.reportedAt);
      expect(back.createdAt, original.createdAt);
    });

    test('fromJson: solo las señales en true entran al set', () {
      final json = _event().toJson()
        ..['alarm_signs'] = {
          'fiebre_38': true,
          'sangrado_10min': false,
          'linfangitis': true,
        };
      final e = AdverseEvent.fromJson(json);
      expect(e.alarmSigns, {
        AdverseEventAlarmSign.fiebre38,
        AdverseEventAlarmSign.linfangitis,
      });
    });

    test('fromJson tolera alarm_signs ausente/vacío', () {
      final json = _event().toJson()..remove('alarm_signs');
      expect(AdverseEvent.fromJson(json).alarmSigns, isEmpty);
    });
  });
}
