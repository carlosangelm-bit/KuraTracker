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
import 'dart:math' as math;
import 'dart:typed_data';

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

  // Brillos especulares (tejido húmedo, flash, luz rasante). Un reflejo es
  // CLARO y DESATURADO — exactamente la firma de la epitelización —, así que
  // sin filtrarlo el motor lee los reflejos como cicatrización: medido, hasta
  // 62 % de epitelización inventada. Es el peor error posible en seguimiento:
  // un falso positivo de mejoría.
  group('brillos especulares', () {
    final engine = WoundVisionEngine(spec: spec, params: params);

    /// Añade manchas blancas saturadas dentro de la herida.
    RgbRaster conReflejos(RgbRaster src, SceneTruth truth, double cobertura) {
      final out = RgbRaster(src.width, src.height, Uint8List.fromList(src.data));
      if (cobertura <= 0) return out;
      final rnd = math.Random(4);
      final ppm = truth.pxPerMm;
      final cx = truth.woundCenterMm.x * ppm, cy = truth.woundCenterMm.y * ppm;
      final a = 20.0 * ppm, b = 12.0 * ppm;
      final sig = math.sqrt(cobertura * math.pi * a * b / (12 * math.pi));
      for (var k = 0; k < 12; k++) {
        final t = rnd.nextDouble() * 2 * math.pi, rr = math.sqrt(rnd.nextDouble()) * 0.8;
        final mx = cx + a * rr * math.cos(t), my = cy + b * rr * math.sin(t);
        for (var y = (my - 3 * sig).floor(); y < (my + 3 * sig).ceil(); y++) {
          for (var x = (mx - 3 * sig).floor(); x < (mx + 3 * sig).ceil(); x++) {
            if (x < 0 || y < 0 || x >= out.width || y >= out.height) continue;
            final d2 = (x - mx) * (x - mx) + (y - my) * (y - my);
            final g = math.exp(-d2 / (2 * sig * sig));
            final i = (y * out.width + x) * 3;
            for (var c = 0; c < 3; c++) {
              out.data[i + c] = (out.data[i + c] + 255 * g * 1.2).round().clamp(0, 255);
            }
          }
        }
      }
      return out;
    }

    test('los reflejos NO se cuentan como epitelización', () {
      final (metric, truth) = renderScene(spec);
      final conBrillo = conReflejos(metric, truth, 0.30);
      final (photo, _) = perspectivePhoto(conBrillo, truth.pxPerMm, tilt: 0.10);
      final outcome = engine.calibratePhotoRaster(photo);
      final res = engine.analyze(outcome, seeds: [seedFor(outcome.result!, truth.woundCenterMm)]);
      expect(res, isNotNull);
      // Sin el filtro esto llegaba a 43–62 %. La verdad de la escena es 0 %.
      expect(res!.tissue.epitelizacion, lessThan(20),
          reason: 'epitelización ${res.tissue.epitelizacion} % — los brillos se están leyendo como cicatrización');
      // Y el resto del lecho sigue reconociéndose. El reparto es sobre el tejido
      // EVALUABLE (lo no quemado): con 12 reflejos gaussianos cuyos footprints 3σ
      // se solapan, ~68 % de la herida queda quemada (specularFraction≈0.68;
      // los píxeles marcados promedian S≈0,03 y V≈0,95 — genuinamente blancos,
      // no granulación sana en el borde del umbral). Como los reflejos caen al
      // CENTRO (granulación), lo evaluable es sobre todo esfacelo periférico, así
      // que la granulación evaluable ronda 20-25 %, no >35. Lo que importa es que
      // sigue presente (no todo se leyó como epitelización/quemado): >15.
      expect(res.tissue.granulacion, greaterThan(15));
      expect(res.tissue.esfacelo, greaterThan(15));
      final gate = res.gates.firstWhere((g) => g.id == 'brillo');
      expect(gate.status, GateStatus.warn, reason: gate.detail);
      expect(gate.detail, contains('no se puede evaluar'));
    });

    test('sin reflejos, la compuerta pasa y no se descarta nada', () {
      final (metric, truth) = renderScene(spec);
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.10);
      final outcome = engine.calibratePhotoRaster(photo);
      final res = engine.analyze(outcome, seeds: [seedFor(outcome.result!, truth.woundCenterMm)])!;
      final gate = res.gates.firstWhere((g) => g.id == 'brillo');
      expect(gate.status, GateStatus.pass);
      expect((res.tissue.granulacion - 60).abs(), lessThanOrEqualTo(3));
    });
  });
}
