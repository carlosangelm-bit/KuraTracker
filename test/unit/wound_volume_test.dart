import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/core/utils/wound_volume.dart';
import 'package:kuratracker/models/wound.dart';

/// Pruebas de la formula de Kundin (feat/volume-kundin-charts):
/// V (cm3) = Largo x Ancho x Profundidad x 0.327, editable por el clinico,
/// con deteccion de sobrescritura manual (volume_manual) por tolerancia.
void main() {
  group('WoundVolumeCalculator.kundin', () {
    test('calcula V = L x A x P x 0.327 para una herida profunda', () {
      final v = WoundVolumeCalculator.kundin(lengthCm: 4, widthCm: 3, depthCm: 2);
      // 4 * 3 * 2 * 0.327 = 7.848
      expect(v, closeTo(7.848, 1e-9));
    });

    test('depthCm null -> null (herida superficial, sin medicion 3D)', () {
      final v = WoundVolumeCalculator.kundin(lengthCm: 4, widthCm: 3, depthCm: null);
      expect(v, isNull);
    });

    test('depthCm == 0 -> null (no se fuerza un valor de 0)', () {
      final v = WoundVolumeCalculator.kundin(lengthCm: 4, widthCm: 3, depthCm: 0);
      expect(v, isNull);
    });

    test('depthCm negativo (dato invalido) -> null', () {
      final v = WoundVolumeCalculator.kundin(lengthCm: 4, widthCm: 3, depthCm: -1);
      expect(v, isNull);
    });

    test('lengthCm o widthCm en 0 -> null aunque haya profundidad', () {
      expect(WoundVolumeCalculator.kundin(lengthCm: 0, widthCm: 3, depthCm: 2), isNull);
      expect(WoundVolumeCalculator.kundin(lengthCm: 4, widthCm: 0, depthCm: 2), isNull);
    });

    test('constante publica coincide con la especificacion clinica (0.327)', () {
      expect(WoundVolumeCalculator.kundinConstant, 0.327);
    });
  });

  group('WoundVolumeCalculator.isManualOverride', () {
    test('false cuando el valor guardado coincide exactamente con el auto-calculo', () {
      final auto = WoundVolumeCalculator.kundin(lengthCm: 4, widthCm: 3, depthCm: 2);
      final manual = WoundVolumeCalculator.isManualOverride(
        storedVolumeCm3: auto,
        autoCalculatedCm3: auto,
      );
      expect(manual, isFalse);
    });

    test('false cuando la diferencia esta dentro de la tolerancia de redondeo (<=0.01)', () {
      final manual = WoundVolumeCalculator.isManualOverride(
        storedVolumeCm3: 7.849,
        autoCalculatedCm3: 7.848,
      );
      expect(manual, isFalse);
    });

    test('true cuando el clinico sobrescribe con un valor que difiere mas de la tolerancia', () {
      final manual = WoundVolumeCalculator.isManualOverride(
        storedVolumeCm3: 9.0,
        autoCalculatedCm3: 7.848,
      );
      expect(manual, isTrue);
    });

    test('true cuando hay valor guardado pero el auto-calculo es null (herida se volvio superficial)', () {
      final manual = WoundVolumeCalculator.isManualOverride(
        storedVolumeCm3: 7.848,
        autoCalculatedCm3: null,
      );
      expect(manual, isTrue);
    });

    test('true cuando no hay valor guardado pero si auto-calculo (campo vaciado manualmente)', () {
      final manual = WoundVolumeCalculator.isManualOverride(
        storedVolumeCm3: null,
        autoCalculatedCm3: 7.848,
      );
      expect(manual, isTrue);
    });

    test('false cuando ambos son null (herida superficial, sin ajuste manual)', () {
      final manual = WoundVolumeCalculator.isManualOverride(
        storedVolumeCm3: null,
        autoCalculatedCm3: null,
      );
      expect(manual, isFalse);
    });
  });

  group('WoundMeasurement.volumeManual round-trip (toJson -> fromJson)', () {
    test('preserva volumeCm3 y volumeManual=true', () {
      final original = WoundMeasurement(
        id: 'm1',
        woundId: 'w1',
        measuredAt: DateTime(2026, 1, 15),
        lengthCm: 4,
        widthCm: 3,
        areaCm2: 12,
        depthCm: 2,
        volumeCm3: 9.0,
        volumeManual: true,
      );

      final roundTripped = WoundMeasurement.fromJson(original.toJson());

      expect(roundTripped.volumeCm3, 9.0);
      expect(roundTripped.volumeManual, isTrue);
    });

    test('volumeManual default false cuando no viene en el JSON (compatibilidad con filas legadas)', () {
      final json = {
        'id': 'm2',
        'wound_id': 'w1',
        'measured_at': '2026-01-10',
        'length_cm': 2,
        'width_cm': 2,
        'area_cm2': 4,
        // Sin 'volume_manual' ni 'volume_cm3': fila anterior a la migracion 0015.
      };

      final m = WoundMeasurement.fromJson(json);

      expect(m.volumeCm3, isNull);
      expect(m.volumeManual, isFalse);
    });

    test('herida superficial: volumeCm3 null y volumeManual false se preservan', () {
      final original = WoundMeasurement(
        id: 'm3',
        woundId: 'w1',
        measuredAt: DateTime(2026, 2, 1),
        lengthCm: 3,
        widthCm: 2,
        areaCm2: 6,
        depthCm: 0,
        volumeCm3: null,
        volumeManual: false,
      );

      final roundTripped = WoundMeasurement.fromJson(original.toJson());

      expect(roundTripped.volumeCm3, isNull);
      expect(roundTripped.volumeManual, isFalse);
    });
  });
}
