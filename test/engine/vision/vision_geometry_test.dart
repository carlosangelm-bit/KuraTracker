import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/vision/rasters.dart';
import 'package:kuratracker/engine/vision/vision_geometry.dart';

void main() {
  group('Homography', () {
    test('4 puntos: mapea exactamente las correspondencias y su inversa las deshace', () {
      final src = [const Pt(0, 0), const Pt(100, 0), const Pt(100, 60), const Pt(0, 60)];
      final dst = [const Pt(12, 8), const Pt(130, 20), const Pt(118, 90), const Pt(3, 70)];
      final h = Homography.fromFourPoints(src, dst)!;
      for (var i = 0; i < 4; i++) {
        expect(h.apply(src[i]).distanceTo(dst[i]), lessThan(1e-6));
      }
      final inv = h.inverse!;
      const p = Pt(37, 21);
      expect(inv.apply(h.apply(p)).distanceTo(p), lessThan(1e-6));
      final id = h.compose(inv);
      expect(id.apply(p).distanceTo(p), lessThan(1e-6));
    });

    test('puntos colineales → null', () {
      final src = [const Pt(0, 0), const Pt(1, 1), const Pt(2, 2), const Pt(3, 3)];
      final dst = [const Pt(0, 0), const Pt(1, 0), const Pt(1, 1), const Pt(0, 1)];
      expect(Homography.fromFourPoints(src, dst), isNull);
    });
  });

  group('Poly', () {
    test('envolvente, Feret y ancho de un rectángulo rotado', () {
      final pts = <Pt>[];
      const th = 0.6;
      for (var i = 0; i <= 40; i++) {
        for (var j = 0; j <= 20; j++) {
          final x = i * 1.0, y = j * 1.0;
          pts.add(Pt(x * math.cos(th) - y * math.sin(th), x * math.sin(th) + y * math.cos(th)));
        }
      }
      final hull = Poly.convexHull(pts);
      expect(hull.length, inInclusiveRange(4, 8));
      final (a, b, d) = Poly.maxFeret(hull);
      expect(d, closeTo(math.sqrt(40 * 40 + 20 * 20), 1e-6));
      final axis = (b - a) * (1 / d);
      final (mn, mx) = Poly.extentAlong(hull, axis.perp);
      // Extensión perpendicular a la diagonal de un rectángulo 40×20.
      expect(mx - mn, closeTo(2 * 40 * 20 / d, 1e-6));
      expect(Poly.area(hull), closeTo(800, 1e-6));
      expect(Poly.perimeter(hull), closeTo(120, 1e-6));
    });

    test('Douglas–Peucker conserva un polígono ya simple', () {
      final sq = [const Pt(0, 0), const Pt(10, 0), const Pt(10, 10), const Pt(0, 10)];
      final s = Poly.simplifyClosed(sq, 0.5);
      expect(s.length, 4);
      expect(Poly.area(s), closeTo(100, 1e-9));
    });

    test('isConvexQuad', () {
      expect(Poly.isConvexQuad([const Pt(0, 0), const Pt(10, 0), const Pt(10, 10), const Pt(0, 10)]), isTrue);
      expect(Poly.isConvexQuad([const Pt(0, 0), const Pt(10, 0), const Pt(2, 2), const Pt(0, 10)]), isFalse);
    });
  });

  group('BitMask', () {
    test('etiquetado, relleno de huecos y contorno de un anillo', () {
      final m = BitMask(40, 40);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          final d = math.sqrt(math.pow(x + 0.5 - 20, 2) + math.pow(y + 0.5 - 20, 2));
          if (d <= 15 && d >= 8) m.set(x, y, true);
        }
      }
      final (_, n) = m.label();
      expect(n, 1);
      final filled = m.fillHoles();
      expect(filled.count, greaterThan(m.count));
      // El disco relleno tiene ≈ π·15² píxeles.
      expect(filled.count, closeTo(math.pi * 225, 15));
      final contour = filled.traceOuterContour();
      expect(contour.length, greaterThan(60));
      // Cierra sin saltos (8-vecindad).
      for (var i = 0; i < contour.length; i++) {
        expect(contour[i].distanceTo(contour[(i + 1) % contour.length]), lessThanOrEqualTo(math.sqrt2 + 1e-9));
      }
      final simple = Poly.simplifyClosed(contour, 1.0);
      expect(Poly.perimeter(simple), closeTo(2 * math.pi * 15, 6));
    });

    test('keepComponentsContaining conserva solo la componente de la semilla', () {
      final m = BitMask(20, 10);
      m.fillRect(0, 0, 5, 10, true);
      m.fillRect(10, 0, 20, 10, true);
      final kept = m.keepComponentsContaining([const Pt(12, 3)]);
      expect(kept.count, 100);
      expect(kept.get(2, 2), isFalse);
    });
  });
}
