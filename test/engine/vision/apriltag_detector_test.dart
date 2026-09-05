// Detector AprilTag 36h11 en Dart puro: sobre una tarjeta sintética con
// perspectiva conocida debe encontrar los 4 tags, decodificarlos sin errores
// de bit y ubicar sus centros con error sub-píxel o cercano.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/vision/apriltag_detector.dart';
import 'package:kuratracker/engine/vision/vision_geometry.dart';

import 'synthetic_scene.dart';

void main() {
  final spec = loadTestCardSpec();
  final params = loadTestVisionParams();
  final detector = AprilTagDetector(params.tagDetector);

  for (final tilt in [0.0, 0.12, 0.22]) {
    test('detecta y decodifica los 4 tags con perspectiva tilt=$tilt', () {
      final (metric, truth) = renderScene(spec);
      final (photo, hMmToPx) = perspectivePhoto(metric, truth.pxPerMm, tilt: tilt);
      final dets = detector.detect(photo);
      final byId = {for (final d in dets) d.id: d};
      expect(byId.keys.toSet(), containsAll(spec.tagIds), reason: 'faltan tags: $byId');
      for (final t in spec.tags) {
        final d = byId[t.id]!;
        expect(d.hamming, 0, reason: 'tag ${t.id} con bits erróneos');
        final expected = hMmToPx.apply(t.centerMm);
        expect(d.center.distanceTo(expected), lessThan(2.0),
            reason: 'centro del tag ${t.id}: ${d.center} vs $expected');
        // Esquinas: cada esquina real debe tener una detectada a < 1.5 px.
        final s = t.sizeMm / 2;
        for (final off in [Pt(-s, -s), Pt(s, -s), Pt(s, s), Pt(-s, s)]) {
          final tc = hMmToPx.apply(t.centerMm + off);
          final best = d.corners.map((c) => c.distanceTo(tc)).reduce((a, b) => a < b ? a : b);
          expect(best, lessThan(1.5), reason: 'esquina del tag ${t.id}');
        }
      }
    });
  }

  test('sin tarjeta no inventa detecciones', () {
    final (metric, truth) = renderScene(spec, discFallback: true);
    final (photo, _) = perspectivePhoto(metric, truth.pxPerMm, tilt: 0.05);
    final dets = detector.detect(photo);
    expect(dets, isEmpty);
  });
}
