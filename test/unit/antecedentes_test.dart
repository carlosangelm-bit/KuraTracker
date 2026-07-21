// Tests de antecedentes (Fase 3): AHF (heredo-familiares) + APNP serializados
// en el modelo Patient.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/antecedentes.dart';
import 'package:kuratracker/models/patient.dart';

void main() {
  group('Enums de antecedentes', () {
    test('AHF dbValue/fromDb roundtrip + desconocido null', () {
      for (final v in AntecedenteHeredoFamiliar.values) {
        expect(AntecedenteHeredoFamiliarX.fromDb(v.dbValue), v);
      }
      expect(AntecedenteHeredoFamiliarX.fromDb('zzz'), isNull);
    });

    test('APNP enums fromDb null-safe', () {
      expect(TabaquismoEstadoX.fromDb(null), isNull);
      expect(TabaquismoEstadoX.fromDb('activo'), TabaquismoEstado.activo);
      expect(ConsumoAlcoholX.fromDb('ocasional'), ConsumoAlcohol.ocasional);
      expect(ActividadFisicaX.fromDb('sedentario'), ActividadFisica.sedentario);
    });
  });

  group('Patient — antecedentes', () {
    test('roundtrip conserva AHF (set) y APNP', () {
      final p = Patient(
        id: 'p1',
        folio: 'EXP2026-0001',
        fullName: 'X',
        createdAt: DateTime(2026, 7, 21),
        familyHistory: {
          AntecedenteHeredoFamiliar.diabetes,
          AntecedenteHeredoFamiliar.hipertension,
        },
        familyHistoryNotes: 'Madre diabética',
        smoking: TabaquismoEstado.exfumador,
        alcohol: ConsumoAlcohol.ocasional,
        physicalActivity: ActividadFisica.ligera,
        apnpNotes: 'Sin toxicomanías',
      );
      final back = Patient.fromJson(p.toJson());
      expect(back.familyHistory, {
        AntecedenteHeredoFamiliar.diabetes,
        AntecedenteHeredoFamiliar.hipertension,
      });
      expect(back.familyHistoryNotes, 'Madre diabética');
      expect(back.smoking, TabaquismoEstado.exfumador);
      expect(back.alcohol, ConsumoAlcohol.ocasional);
      expect(back.physicalActivity, ActividadFisica.ligera);
      expect(back.apnpNotes, 'Sin toxicomanías');
    });

    test('family_history serializa como lista de nombres', () {
      final p = Patient(
        id: 'p2',
        folio: 'EXP2026-0002',
        fullName: 'X',
        createdAt: DateTime(2026, 7, 21),
        familyHistory: {AntecedenteHeredoFamiliar.cancer},
      );
      expect(p.toJson()['family_history'], ['cancer']);
    });

    test('ausencia de antecedentes -> set vacío / null (compat)', () {
      final p = Patient.fromJson({
        'id': 'p3',
        'folio': 'EXP2026-0003',
        'full_name': 'X',
        'created_at': DateTime(2026, 7, 21).toIso8601String(),
      });
      expect(p.familyHistory, isEmpty);
      expect(p.smoking, isNull);
      expect(p.apnpNotes, isNull);
    });

    test('valores desconocidos en family_history se ignoran', () {
      final p = Patient.fromJson({
        'id': 'p4',
        'folio': 'EXP2026-0004',
        'full_name': 'X',
        'created_at': DateTime(2026, 7, 21).toIso8601String(),
        'family_history': ['diabetes', 'zzz-inexistente'],
      });
      expect(p.familyHistory, {AntecedenteHeredoFamiliar.diabetes});
    });
  });
}
