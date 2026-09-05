// Normalización de color/exposición con la tarjeta como referencia neutra.
//
// Este test existe porque el clasificador de tejido usa umbrales de tono y
// brillo ABSOLUTOS: sin normalizar, la luz de la sala cambia la composición
// del lecho e incluso rompe la segmentación. Medido aquí mismo con la
// corrección desactivada, bajo lámpara cálida el esfacelo pasa de 30 % a 0 %
// y el área cae ~30 %.
//
// Importa sobre todo para el SEGUIMIENTO SERIAL, que es de lo que vive
// KuraTracker: si los porcentajes del lecho se mueven porque cambió la sala,
// la tendencia entre visitas (y el checkpoint de Sheehan que la consume)
// queda contaminada.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/vision/rasters.dart';
import 'package:kuratracker/engine/vision/vision_geometry.dart';
import 'package:kuratracker/engine/vision/vision_params.dart';
import 'package:kuratracker/engine/vision/wound_vision_engine.dart';

import 'synthetic_scene.dart';

/// Ganancias RGB que simulan la luz de la sala (aprox. von Kries).
const _condiciones = <String, List<double>>{
  'referencia D65': [1.00, 1.00, 1.00],
  // Normalizada para que ningún canal sature el papel de la tarjeta: es lo que
  // hace la auto-exposición del teléfono. El caso que SÍ quema la tarjeta se
  // prueba aparte (compuerta 'clipped').
  'tungsteno (cálida)': [1.00, 0.78, 0.55],
  'sombra (fría)': [0.86, 0.98, 1.22],
  'fluorescente (verde)': [0.95, 1.10, 0.95],
  'subexpuesta -40 %': [0.60, 0.60, 0.60],
  'sobreexpuesta +35 %': [1.35, 1.35, 1.35],
};

RgbRaster _aplicarLuz(RgbRaster src, List<double> gain) {
  final out = RgbRaster(src.width, src.height);
  for (var i = 0; i < src.data.length; i += 3) {
    for (var c = 0; c < 3; c++) {
      out.data[i + c] = (src.data[i + c] * gain[c]).round().clamp(0, 255);
    }
  }
  return out;
}

void main() {
  final spec = loadTestCardSpec();
  final params = loadTestVisionParams();

  Pt seedFor(CalibrationResult cal, Pt mm) {
    final origin = (cal.meta['origin_mm'] as List).cast<num>();
    final ppm = (cal.meta['px_per_mm'] as num).toDouble();
    return Pt((mm.x - origin[0]) * ppm, (mm.y - origin[1]) * ppm);
  }

  /// Corre la cadena completa bajo una luz dada y devuelve (área %, tejido).
  (double, TissueComposition) medirBajoLuz(WoundVisionEngine engine, List<double> gain) {
    final (metric, truth) = renderScene(spec);
    final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.10);
    final outcome = engine.calibratePhotoRaster(_aplicarLuz(photo, gain));
    expect(outcome.failure, isNull, reason: outcome.failure?.message);
    final cal = outcome.result!;
    final res = engine.analyze(outcome, seeds: [seedFor(cal, truth.woundCenterMm)]);
    expect(res, isNotNull, reason: 'la segmentación falló bajo esta luz');
    final errArea = (res!.measurement.areaCm2 * 100 / truth.areaMm2 - 1) * 100;
    return (errArea, res.tissue);
  }

  group('con normalización (por defecto)', () {
    final engine = WoundVisionEngine(spec: spec, params: params);

    _condiciones.forEach((nombre, gain) {
      test('$nombre: área y composición estables', () {
        final (errArea, tejido) = medirBajoLuz(engine, gain);
        expect(errArea.abs(), lessThan(2.0), reason: 'error de área ${errArea.toStringAsFixed(2)} %');
        // Verdad de la escena: 60 / 30 / 10 / 0.
        expect((tejido.granulacion - 60).abs(), lessThanOrEqualTo(3), reason: 'granulación ${tejido.granulacion}');
        expect((tejido.esfacelo - 30).abs(), lessThanOrEqualTo(3), reason: 'esfacelo ${tejido.esfacelo}');
        expect((tejido.necrosis - 10).abs(), lessThanOrEqualTo(3), reason: 'necrosis ${tejido.necrosis}');
      });
    });

    test('la compuerta de color reporta el desbalance corregido', () {
      final (metric, truth) = renderScene(spec);
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.10);
      final outcome = engine.calibratePhotoRaster(_aplicarLuz(photo, _condiciones['tungsteno (cálida)']!));
      final gate = outcome.result!.gates.firstWhere((g) => g.id == 'color');
      expect(gate.status, GateStatus.pass, reason: gate.detail);
      final illum = outcome.result!.meta['illumination'] as Map<String, dynamic>;
      // Luz cálida: la ganancia del azul debe ser mayor que la del rojo.
      final gain = (illum['gain'] as List).cast<num>();
      expect(gain[2], greaterThan(gain[0]));
      expect(illum['cast_ratio'], greaterThan(1.3));
    });

    test('si la tarjeta sale quemada, corrige pero lo advierte', () {
      // Luz cálida SIN compensar la exposición: el papel satura en el canal rojo.
      final (metric, truth) = renderScene(spec);
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.10);
      final outcome = engine.calibratePhotoRaster(_aplicarLuz(photo, const [1.28, 1.00, 0.70]));
      final illum = outcome.result!.meta['illumination'] as Map<String, dynamic>;
      expect(illum['clipped'], isTrue);
      final gate = outcome.result!.gates.firstWhere((g) => g.id == 'color');
      expect(gate.status, GateStatus.warn);
      expect(gate.detail, contains('quemada'));
      // Aun así la medida se recupera: la advertencia es de prudencia, no de fallo.
      final res = engine.analyze(outcome, seeds: [seedFor(outcome.result!, truth.woundCenterMm)])!;
      expect((res.measurement.areaCm2 * 100 / truth.areaMm2 - 1).abs(), lessThan(0.02));
      expect((res.tissue.esfacelo - 30).abs(), lessThanOrEqualTo(3));
    });

    test('el disco de respaldo avisa que NO normaliza el color', () {
      final (metric, truth) = renderScene(spec, discFallback: true, discDiameterMm: params.discDiameterMm);
      final (photo, _) = topDownPhoto(metric, truth.pxPerMm);
      final outcome = engine.calibratePhotoRaster(photo);
      final gate = outcome.result!.gates.firstWhere((g) => g.id == 'color');
      expect(gate.status, GateStatus.warn);
      expect(gate.detail, contains('NO se normaliza'));
    });
  });

  group('sin normalización (regresión: por qué existe)', () {
    // Mismo motor con illumination.enabled = false.
    final sinCorregir = VisionParams.fromJsonString(
      loadTestVisionParamsJson().replaceFirst('"enabled": true', '"enabled": false'),
    );
    final engine = WoundVisionEngine(spec: spec, params: sinCorregir);

    test('la luz cálida destruye el esfacelo y encoge el área', () {
      final (errArea, tejido) = medirBajoLuz(engine, _condiciones['tungsteno (cálida)']!);
      expect(tejido.esfacelo, lessThan(10), reason: 'sin corregir, el esfacelo amarillo deja de detectarse');
      expect(errArea, lessThan(-10), reason: 'sin corregir, la segmentación pierde parte del lecho');
    });

    test('la subexposición produce el mismo daño', () {
      final (errArea, tejido) = medirBajoLuz(engine, _condiciones['subexpuesta -40 %']!);
      expect(tejido.esfacelo, lessThan(10));
      expect(errArea, lessThan(-10));
    });

    test('la compuerta avisa que el color no se normalizó', () {
      final (metric, truth) = renderScene(spec);
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.10);
      final outcome = engine.calibratePhotoRaster(photo);
      final gate = outcome.result!.gates.firstWhere((g) => g.id == 'color');
      expect(gate.status, GateStatus.warn);
    });
  });
}
