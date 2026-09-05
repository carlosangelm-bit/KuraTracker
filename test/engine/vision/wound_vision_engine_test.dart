// Motor de visión de heridas — validación de la cadena completa sobre escenas
// sintéticas con verdad geométrica conocida (misma metodología que la
// validación sintética del prototipo Python, tools/wound_calibrate_proto).
//
// Criterios (README del prototipo): error de área < 5 %, error de largo < 3 %,
// cross-check del círculo ±3 %. El motor Dart está muy por debajo en sintético;
// la validación con fotos reales + tarjeta impresa sigue pendiente.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/vision/vision_geometry.dart';
import 'package:kuratracker/engine/vision/wound_vision_engine.dart';
import 'package:kuratracker/engine/vision/wound_vision_models.dart';

import 'synthetic_scene.dart';

void main() {
  final spec = loadTestCardSpec();
  final params = loadTestVisionParams();
  final engine = WoundVisionEngine(spec: spec, params: params);

  /// Semilla en px rectificados para un punto en mm (origen de la rectificada
  /// viene en calibration.meta['origin_mm']).
  Pt seedFor(CalibrationResult cal, Pt mm) {
    final origin = (cal.meta['origin_mm'] as List).cast<num>();
    final ppm = (cal.meta['px_per_mm'] as num).toDouble();
    return Pt((mm.x - origin[0]) * ppm, (mm.y - origin[1]) * ppm);
  }

  group('tarjeta WoundCalibrate', () {
    for (final tilt in [0.0, 0.12, 0.22]) {
      for (final axes in [(20.0, 12.0), (8.0, 6.0), (35.0, 15.0)]) {
        test('mide área/largo/ancho y tejido (tilt=$tilt, semiejes=$axes)', () {
          final (metric, truth) = renderScene(spec, woundA: axes.$1, woundB: axes.$2);
          final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: tilt);
          final outcome = engine.calibratePhotoRaster(photo);
          expect(outcome.failure, isNull, reason: outcome.failure?.message);
          final cal = outcome.result!;
          expect(cal.mode, CalibrationMode.card);
          // Compuertas de geometría.
          final planarity = cal.gates.firstWhere((g) => g.id == 'planarity');
          expect(planarity.status, GateStatus.pass, reason: planarity.detail);
          final scale = cal.gates.firstWhere((g) => g.id == 'scale_check');
          expect(scale.status, GateStatus.pass, reason: scale.detail);
          expect(((cal.meta['circle_dev_pct'] as num).abs()), lessThan(3.0));

          final res = engine.analyze(outcome, seeds: [seedFor(cal, truth.woundCenterMm)]);
          expect(res, isNotNull);
          final m = res!.measurement;
          expect((m.areaCm2 * 100 / truth.areaMm2 - 1).abs(), lessThan(0.03), reason: 'área ${m.areaCm2} cm²');
          expect((m.lengthCm * 10 / truth.lengthMm - 1).abs(), lessThan(0.03), reason: 'largo ${m.lengthCm} cm');
          expect((m.widthCm * 10 / truth.widthMm - 1).abs(), lessThan(0.03), reason: 'ancho ${m.widthCm} cm');
          expect((m.perimeterCm * 10 / truth.perimeterMm - 1).abs(), lessThan(0.05), reason: 'perímetro');
          expect((res.tissue.granulacion - truth.granPct).abs(), lessThanOrEqualTo(4));
          expect((res.tissue.esfacelo - truth.sloughPct).abs(), lessThanOrEqualTo(4));
          expect((res.tissue.necrosis - truth.necroPct).abs(), lessThanOrEqualTo(4));
          expect(res.tissue.granulacion + res.tissue.esfacelo + res.tissue.necrosis + res.tissue.epitelizacion, 100);
          expect(res.measurementSource, 'vision_card');
          expect(res.overlayPng, isNotEmpty);
        });
      }
    }

    test('el anillo de epitelización se incluye al marcar una semilla sobre él', () {
      final (metric, truth) = renderScene(spec, woundA: 18, woundB: 11, necroFrac: 0, epithelialRim: true);
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.12);
      final outcome = engine.calibratePhotoRaster(photo);
      final cal = outcome.result!;
      // Sin semilla en el anillo: solo el lecho.
      final bed = engine.analyze(outcome, seeds: [seedFor(cal, truth.woundCenterMm)])!;
      expect((bed.measurement.areaCm2 * 100 / truth.areaMm2 - 1).abs(), lessThan(0.05));
      expect(bed.tissue.epitelizacion, lessThan(5));
      // Con semilla sobre el anillo (a 19,5 mm del centro sobre el eje mayor).
      const th = 20 * math.pi / 180;
      final rim = Pt(truth.woundCenterMm.x + 19.5 * math.cos(th), truth.woundCenterMm.y + 19.5 * math.sin(th));
      final full = engine.analyze(outcome, seeds: [seedFor(cal, truth.woundCenterMm), seedFor(cal, rim)])!;
      final rimAreaMm2 = math.pi * 21 * 14;
      expect((full.measurement.areaCm2 * 100 / rimAreaMm2 - 1).abs(), lessThan(0.05));
      expect(full.tissue.epitelizacion, greaterThan(20));
      expect((full.measurement.lengthCm * 10 / 42 - 1).abs(), lessThan(0.04));
    });

    test('con 4 tags parcialmente fuera de la foto reporta el fallo, no una medida', () {
      final (metric, truth) = renderScene(spec);
      // Recortar la foto para que se pierdan los tags de la izquierda.
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.0);
      final cropped = photo.crop(photo.width ~/ 3, 0, photo.width - photo.width ~/ 3, photo.height);
      final outcome = engine.calibratePhotoRaster(cropped);
      // Sin tarjeta ni disco: fallo con motivo legible.
      expect(outcome.result, isNull);
      expect(outcome.failure, isNotNull);
      expect(outcome.failure!.message, isNotEmpty);
    });
  });

  group('disco de respaldo', () {
    test('escala por disco en foto cenital', () {
      final (metric, truth) = renderScene(spec, discFallback: true, discDiameterMm: params.discDiameterMm);
      final (photo, hMmToPx) = topDownPhoto(metric, truth.pxPerMm, angleDeg: 7, scale: 0.9);
      final outcome = engine.calibratePhotoRaster(photo);
      expect(outcome.failure, isNull, reason: outcome.failure?.message);
      final cal = outcome.result!;
      expect(cal.mode, CalibrationMode.disc);
      final tilt = cal.gates.firstWhere((g) => g.id == 'disc_tilt');
      expect(tilt.status, GateStatus.pass, reason: tilt.detail);
      final seedPhoto = hMmToPx.apply(truth.woundCenterMm);
      final seedRect = cal.photoToRectified.apply(seedPhoto);
      final res = engine.analyze(outcome, seeds: [seedRect]);
      expect(res, isNotNull);
      expect((res!.measurement.areaCm2 * 100 / truth.areaMm2 - 1).abs(), lessThan(0.05));
      expect((res.measurement.lengthCm * 10 / truth.lengthMm - 1).abs(), lessThan(0.05));
      expect(res.measurementSource, 'vision_disc');
      expect(res.gates.any((g) => g.id == 'perspective' && g.status == GateStatus.warn), isTrue);
    });

    test('disco visto en oblicuo dispara la compuerta de foto cenital', () {
      final (metric, truth) = renderScene(spec, discFallback: true, discDiameterMm: params.discDiameterMm);
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.0); // anisotrópica
      final outcome = engine.calibratePhotoRaster(photo);
      // O no lo encuentra (aspecto fuera de rango) o lo encuentra con la compuerta en fail.
      if (outcome.result != null) {
        final tilt = outcome.result!.gates.firstWhere((g) => g.id == 'disc_tilt');
        expect(tilt.status, GateStatus.fail);
      } else {
        expect(outcome.failure, isNotNull);
      }
    });
  });

  group('trazo manual', () {
    test('mide un rectángulo trazado a mano exactamente', () {
      final (metric, truth) = renderScene(spec);
      final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.1);
      final outcome = engine.calibratePhotoRaster(photo);
      final cal = outcome.result!;
      // Rectángulo de 30 × 20 mm alrededor del centro de la herida.
      final c = truth.woundCenterMm;
      final poly = [
        seedFor(cal, Pt(c.x - 15, c.y - 10)),
        seedFor(cal, Pt(c.x + 15, c.y - 10)),
        seedFor(cal, Pt(c.x + 15, c.y + 10)),
        seedFor(cal, Pt(c.x - 15, c.y + 10)),
      ];
      final res = engine.analyzeManualTrace(outcome, polygon: poly)!;
      expect(res.manualTrace, isTrue);
      expect(res.measurementSource, 'vision_manual_trace');
      expect(res.measurement.areaCm2, closeTo(6.0, 0.05));
      // Largo = diagonal (Feret máximo), ancho = extensión perpendicular a la diagonal.
      expect(res.measurement.lengthCm, closeTo(3.606, 0.03));
      expect(res.measurement.perimeterCm, closeTo(10.0, 0.05));
      expect(res.tissue.granulacion + res.tissue.esfacelo + res.tissue.necrosis + res.tissue.epitelizacion, 100);
    });
  });

  test('vision_meta es serializable y lleva versión, modo y compuertas', () {
    final (metric, truth) = renderScene(spec);
    final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.1);
    final outcome = engine.calibratePhotoRaster(photo);
    final res = engine.analyze(outcome, seeds: [seedFor(outcome.result!, truth.woundCenterMm)])!;
    final meta = res.toVisionMeta();
    expect(meta['engine_version'], startsWith('kura-vision/'));
    expect(meta['mode'], 'card');
    expect((meta['gates'] as List), isNotEmpty);
    expect((meta['contour_px'] as List).length, greaterThan(8));
    expect(meta['mm_per_px'], closeTo(0.25, 0.01));
  });
}
