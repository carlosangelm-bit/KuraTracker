// Tests de la ficha de identificación NOM-004 (Fase 2): serialización + IMC.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/patient.dart';

void main() {
  group('Patient — identificación NOM-004', () {
    test('roundtrip toJson/fromJson conserva los campos nuevos', () {
      final p = Patient(
        id: 'p1',
        folio: 'EXP2026-0001',
        fullName: 'Juan Pérez',
        createdAt: DateTime(2026, 7, 21),
        curp: 'PERJ800101HDFRRN09',
        address: 'Calle 1 #2, CDMX',
        occupation: 'Jubilado',
        responsibleName: 'Ana Pérez',
        responsibleRelationship: 'Hija',
        responsiblePhone: '5551234567',
        weightKg: 80,
        heightCm: 175,
      );
      final back = Patient.fromJson(p.toJson());
      expect(back.curp, 'PERJ800101HDFRRN09');
      expect(back.address, 'Calle 1 #2, CDMX');
      expect(back.occupation, 'Jubilado');
      expect(back.responsibleName, 'Ana Pérez');
      expect(back.responsibleRelationship, 'Hija');
      expect(back.responsiblePhone, '5551234567');
      expect(back.weightKg, 80);
      expect(back.heightCm, 175);
    });

    test('IMC se calcula de peso/talla (kg/m²)', () {
      final p = Patient(
        id: 'p2',
        folio: 'EXP2026-0002',
        fullName: 'X',
        createdAt: DateTime(2026, 7, 21),
        weightKg: 80,
        heightCm: 200, // 2 m -> IMC 20
      );
      expect(p.bmi, closeTo(20.0, 1e-9));
    });

    test('IMC null si falta peso o talla', () {
      final p = Patient(
        id: 'p3',
        folio: 'EXP2026-0003',
        fullName: 'X',
        createdAt: DateTime(2026, 7, 21),
        weightKg: 80,
      );
      expect(p.bmi, isNull);
    });

    test('campos ausentes -> null (compatibilidad hacia atrás)', () {
      final p = Patient.fromJson({
        'id': 'p4',
        'folio': 'EXP2026-0004',
        'full_name': 'Sin identificación',
        'created_at': DateTime(2026, 7, 21).toIso8601String(),
      });
      expect(p.curp, isNull);
      expect(p.address, isNull);
      expect(p.weightKg, isNull);
      expect(p.bmi, isNull);
    });
  });
}
