// Trazo ENVOLVENTE: el clínico rodea la herida por fuera y el motor busca el
// borde real dentro del lazo.
//
// El diseño parte de aceptar que el dedo SIEMPRE traza por fuera (tapa lo que
// dibuja). En vez de exigir puntería, el trazo deja de ser la medida y pasa a
// ser la región de búsqueda; a cambio, la franja entre el trazo y la herida es
// piel sana garantizada, que es justo el modelo que al motor le costaba armar.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/vision/vision_geometry.dart';
import 'package:kuratracker/engine/vision/wound_vision_engine.dart';

import 'synthetic_scene.dart';

void main() {
  final spec = loadTestCardSpec();
  final params = loadTestVisionParams();
  final engine = WoundVisionEngine(spec: spec, params: params);

  Pt seedFor(CalibrationResult cal, Pt mm) {
    final origin = (cal.meta['origin_mm'] as List).cast<num>();
    final ppm = (cal.meta['px_per_mm'] as num).toDouble();
    return Pt((mm.x - origin[0]) * ppm, (mm.y - origin[1]) * ppm);
  }

  /// Lazo grosero POR FUERA de una herida elíptica, como lo haría un dedo.
  List<Pt> lazo(
    CalibrationResult cal,
    Pt centroMm, {
    required double aMm,
    required double bMm,
    required double anguloDeg,
    required double margenMm,
    required double pulsoMm,
    int puntos = 30,
    int semilla = 5,
  }) {
    final rnd = math.Random(semilla);
    final th = anguloDeg * math.pi / 180;
    final ts = [for (var i = 0; i < puntos; i++) rnd.nextDouble() * 2 * math.pi]..sort();
    return [
      for (final t in ts)
        () {
          // Ruido gaussiano aproximado (suma de uniformes).
          final r = (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * pulsoMm;
          final ra = aMm + margenMm + r, rb = bMm + margenMm + r;
          final dx = ra * math.cos(t), dy = rb * math.sin(t);
          return seedFor(cal, Pt(
            centroMm.x + dx * math.cos(th) - dy * math.sin(th),
            centroMm.y + dx * math.sin(th) + dy * math.cos(th),
          ));
        }()
    ];
  }

  group('el trazo envolvente recupera el borde real', () {
    for (final margen in [4.0, 8.0, 14.0]) {
      test('lazo con ${margen.toStringAsFixed(0)} mm de margen', () {
        final (metric, truth) = renderScene(spec);
        final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.10);
        final outcome = engine.calibratePhotoRaster(photo);
        final cal = outcome.result!;
        final poly = lazo(cal, truth.woundCenterMm,
            aMm: 20, bMm: 12, anguloDeg: 20, margenMm: margen, pulsoMm: 1.2);

        // El área del LAZO sobreestima mucho: por eso el trazo no puede ser la medida.
        final areaLazo = Poly.area(poly) * cal.mmPerPx * cal.mmPerPx;
        expect(areaLazo, greaterThan(truth.areaMm2 * 1.25),
            reason: 'el lazo debe encerrar la herida con holgura');

        final res = engine.analyzeEnclosingTrace(outcome, polygon: poly);
        expect(res, isNotNull);
        final err = (res!.measurement.areaCm2 * 100 / truth.areaMm2 - 1) * 100;
        expect(err.abs(), lessThan(4.0), reason: 'área refinada ${err.toStringAsFixed(1)} %');
        expect((res.tissue.esfacelo - 30).abs(), lessThanOrEqualTo(4));
        // El contorno lo puso el motor, no el dedo: cuenta como medición automática.
        expect(res.manualTrace, isFalse);
        expect(res.measurementSource, 'vision_card');
        final gate = res.gates.firstWhere((g) => g.id == 'enclosing_trace');
        expect(gate.status, GateStatus.pass, reason: gate.detail);
      });
    }

    test('trazos distintos de la misma herida dan casi el mismo número', () {
      final (metric, truth) = renderScene(spec);
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.10);
      final outcome = engine.calibratePhotoRaster(photo);
      final cal = outcome.result!;
      final areas = <double>[];
      for (var s = 0; s < 5; s++) {
        final poly = lazo(cal, truth.woundCenterMm,
            aMm: 20, bMm: 12, anguloDeg: 20, margenMm: 8, pulsoMm: 1.5, semilla: 100 + s);
        final res = engine.analyzeEnclosingTrace(outcome, polygon: poly);
        if (res != null) areas.add(res.measurement.areaCm2);
      }
      expect(areas.length, greaterThanOrEqualTo(4));
      final media = areas.reduce((a, b) => a + b) / areas.length;
      final disp = (areas.reduce(math.max) - areas.reduce(math.min)) / media * 100;
      // Trazar a mano el borde exacto daba ±2–8 % entre repeticiones.
      expect(disp, lessThan(4.0), reason: 'dispersión entre trazos ${disp.toStringAsFixed(1)} %');
    });

    test('si el trazo se mete DENTRO de la herida, avisa', () {
      final (metric, truth) = renderScene(spec);
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.10);
      final outcome = engine.calibratePhotoRaster(photo);
      final cal = outcome.result!;
      // Lazo claramente por dentro: corta la lesión.
      final poly = lazo(cal, truth.woundCenterMm,
          aMm: 20, bMm: 12, anguloDeg: 20, margenMm: -6, pulsoMm: 0.5);
      final res = engine.analyzeEnclosingTrace(outcome, polygon: poly);
      expect(res, isNotNull);
      final gate = res!.gates.firstWhere((g) => g.id == 'enclosing_trace');
      expect(gate.status, GateStatus.warn);
      expect(gate.detail, contains('FUERA'));
    });
  });
}
