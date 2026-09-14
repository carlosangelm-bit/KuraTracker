import 'dart:math' as math;
import 'dart:typed_data';

import 'rasters.dart';
import 'tag36h11_table.dart';
import 'vision_geometry.dart';

/// Un tag detectado y decodificado.
class TagDetection {
  final int id;
  final int hamming;
  final int rotation; // 0..3 (múltiplos de 90° horario respecto al canónico)
  final Pt center; // px, resolución completa
  final List<Pt> corners; // 4 esquinas del cuadrado negro exterior (px, res. completa)
  final double sidePx; // lado promedio en px (proxy de distancia)

  const TagDetection({
    required this.id,
    required this.hamming,
    required this.rotation,
    required this.center,
    required this.corners,
    required this.sidePx,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hamming': hamming,
        'center': center.toJson(),
        'corners': [for (final c in corners) c.toJson()],
        'side_px': sidePx,
      };
}

/// Parámetros del detector (todos ajustables desde vision_params.json).
class AprilTagDetectorParams {
  final int detectMaxSide; // lado máximo de la imagen de detección (se reduce por entero)
  final int tileSize; // tile del umbral adaptativo
  final int minContrast; // contraste mínimo (0-255) para considerar un tile
  final int minComponentArea; // px a escala de detección
  final double maxComponentAreaFrac;
  final double minSidePx; // lado mínimo del cuadrilátero (escala de detección)
  final double maxAspect; // lado mayor / lado menor
  final double minHullFill; // área del quad / área de la envolvente
  final int maxHamming;
  final int minDecodeContrast; // blanco exterior − negro del borde
  final int refineSamples;

  const AprilTagDetectorParams({
    this.detectMaxSide = 1000,
    this.tileSize = 4,
    this.minContrast = 40,
    this.minComponentArea = 60,
    this.maxComponentAreaFrac = 0.2,
    this.minSidePx = 8,
    this.maxAspect = 2.5,
    this.minHullFill = 0.8,
    this.maxHamming = 4,
    this.minDecodeContrast = 30,
    this.refineSamples = 16,
  });

  factory AprilTagDetectorParams.fromJson(Map<String, dynamic> j) => AprilTagDetectorParams(
        detectMaxSide: (j['detect_max_side'] as num?)?.toInt() ?? 1000,
        tileSize: (j['tile_size'] as num?)?.toInt() ?? 4,
        minContrast: (j['min_contrast'] as num?)?.toInt() ?? 40,
        minComponentArea: (j['min_component_area'] as num?)?.toInt() ?? 60,
        maxComponentAreaFrac: (j['max_component_area_frac'] as num?)?.toDouble() ?? 0.2,
        minSidePx: (j['min_side_px'] as num?)?.toDouble() ?? 8,
        maxAspect: (j['max_aspect'] as num?)?.toDouble() ?? 2.5,
        minHullFill: (j['min_hull_fill'] as num?)?.toDouble() ?? 0.8,
        maxHamming: (j['max_hamming'] as num?)?.toInt() ?? 4,
        minDecodeContrast: (j['min_decode_contrast'] as num?)?.toInt() ?? 30,
        refineSamples: (j['refine_samples'] as num?)?.toInt() ?? 16,
      );
}

/// Detector de AprilTags de la familia tag36h11 en Dart puro.
///
/// Pipeline (espejo del prototipo validado en Python):
///  1. gris → reducción entera a ≤ [detectMaxSide] px;
///  2. umbral adaptativo por tiles (mín/máx en vecindario 3×3 de tiles);
///  3. componentes conexas oscuras → envolvente convexa → cuadrilátero inicial;
///  4. refinamiento de esquinas a resolución completa por máximo gradiente
///     a lo largo de la normal de cada lado + ajuste de recta por mínimos
///     cuadrados (PCA) e intersección;
///  5. muestreo de la rejilla 8×8 (borde negro + 6×6 de datos) vía homografía
///     y decodificación contra la tabla de 587 códigos (4 rotaciones, Hamming ≤ máx).
class AprilTagDetector {
  final AprilTagDetectorParams params;
  AprilTagDetector([this.params = const AprilTagDetectorParams()]);

  /// Tabla de códigos expandida a bits (587 × 36), una sola vez por proceso.
  static final List<Uint8List> _codeBits = _expandCodes();

  static List<Uint8List> _expandCodes() {
    return [
      for (final hex in kTag36h11CodesHex) _hexToBits(hex),
    ];
  }

  static Uint8List _hexToBits(String hex) {
    // 9 dígitos hex = 36 bits, MSB primero. Se evita int de 36 bits (dart2js).
    final bits = Uint8List(36);
    var k = 0;
    for (var i = 0; i < hex.length; i++) {
      final v = int.parse(hex[i], radix: 16);
      for (var b = 3; b >= 0; b--) {
        if (k < 36) bits[k++] = (v >> b) & 1;
      }
    }
    return bits;
  }

  List<TagDetection> detect(RgbRaster rgb) {
    final grayFull = rgb.toGray();
    return detectGray(grayFull);
  }

  List<TagDetection> detectGray(GrayRaster grayFull) {
    final maxSide = math.max(grayFull.width, grayFull.height);
    final f = maxSide > params.detectMaxSide ? (maxSide / params.detectMaxSide).ceil() : 1;
    final gray = grayFull.downscale(f);
    final dark = _adaptiveDarkMask(gray);
    final (labels, n) = dark.label();
    final w = gray.width, h = gray.height;

    // Agrupar píxeles por etiqueta (bbox + conteo) en un solo barrido.
    final minX = Int32List(n + 1)..fillRange(0, n + 1, w);
    final minY = Int32List(n + 1)..fillRange(0, n + 1, h);
    final maxX = Int32List(n + 1)..fillRange(0, n + 1, -1);
    final maxY = Int32List(n + 1)..fillRange(0, n + 1, -1);
    final area = Int32List(n + 1);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final l = labels[y * w + x];
        if (l == 0) continue;
        area[l]++;
        if (x < minX[l]) minX[l] = x;
        if (x > maxX[l]) maxX[l] = x;
        if (y < minY[l]) minY[l] = y;
        if (y > maxY[l]) maxY[l] = y;
      }
    }

    final maxArea = params.maxComponentAreaFrac * w * h;
    final byId = <int, TagDetection>{};
    for (var l = 1; l <= n; l++) {
      if (area[l] < params.minComponentArea || area[l] > maxArea) continue;
      if (minX[l] == 0 || minY[l] == 0 || maxX[l] == w - 1 || maxY[l] == h - 1) continue;
      // Píxeles de borde de la componente (4-vecindad).
      final boundary = <Pt>[];
      for (var y = minY[l]; y <= maxY[l]; y++) {
        for (var x = minX[l]; x <= maxX[l]; x++) {
          if (labels[y * w + x] != l) continue;
          if (labels[y * w + x - 1] != l ||
              labels[y * w + x + 1] != l ||
              labels[(y - 1) * w + x] != l ||
              labels[(y + 1) * w + x] != l) {
            boundary.add(Pt(x.toDouble(), y.toDouble()));
          }
        }
      }
      final hull = Poly.convexHull(boundary);
      if (hull.length < 4) continue;
      final q0 = _initialQuad(hull);
      if (q0 == null) continue;
      final sides = [for (var k = 0; k < 4; k++) q0[k].distanceTo(q0[(k + 1) % 4])];
      final sMin = sides.reduce(math.min), sMax = sides.reduce(math.max);
      if (sMin < params.minSidePx || sMax / sMin > params.maxAspect) continue;
      final hullArea = Poly.area(hull);
      if (hullArea <= 0 || Poly.area(q0) / hullArea < params.minHullFill) continue;

      // A resolución completa (+0.5: centro del píxel de detección) y refinar.
      final qFull0 = [for (final p in q0) Pt((p.x + 0.5) * f, (p.y + 0.5) * f)];
      final qFull = _refineQuadGradient(qFull0, grayFull, f) ?? qFull0;
      if (!Poly.isConvexQuad(qFull)) continue;

      final dec = _decode(grayFull, qFull);
      if (dec == null) continue;
      final center = dec.h.apply(const Pt(4, 4));
      final sideFull = [for (var k = 0; k < 4; k++) qFull[k].distanceTo(qFull[(k + 1) % 4])];
      final det = TagDetection(
        id: dec.id,
        hamming: dec.hamming,
        rotation: dec.rotation,
        center: center,
        corners: qFull,
        sidePx: sideFull.reduce((a, b) => a + b) / 4,
      );
      final prev = byId[det.id];
      if (prev == null || det.hamming < prev.hamming) byId[det.id] = det;
    }
    return byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  // ---------------------------------------------------------------------------

  BitMask _adaptiveDarkMask(GrayRaster gray) {
    final t = params.tileSize;
    final w = gray.width, h = gray.height;
    final tw = w ~/ t, th = h ~/ t;
    final tMin = Uint8List(tw * th), tMax = Uint8List(tw * th);
    for (var ty = 0; ty < th; ty++) {
      for (var tx = 0; tx < tw; tx++) {
        var mn = 255, mx = 0;
        for (var dy = 0; dy < t; dy++) {
          var k = (ty * t + dy) * w + tx * t;
          for (var dx = 0; dx < t; dx++) {
            final v = gray.data[k++];
            if (v < mn) mn = v;
            if (v > mx) mx = v;
          }
        }
        tMin[ty * tw + tx] = mn;
        tMax[ty * tw + tx] = mx;
      }
    }
    // Mín/máx sobre el vecindario 3×3 de tiles.
    final nMin = Uint8List(tw * th), nMax = Uint8List(tw * th);
    for (var ty = 0; ty < th; ty++) {
      for (var tx = 0; tx < tw; tx++) {
        var mn = 255, mx = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = (ty + dy).clamp(0, th - 1);
          for (var dx = -1; dx <= 1; dx++) {
            final xx = (tx + dx).clamp(0, tw - 1);
            final a = tMin[yy * tw + xx], b = tMax[yy * tw + xx];
            if (a < mn) mn = a;
            if (b > mx) mx = b;
          }
        }
        nMin[ty * tw + tx] = mn;
        nMax[ty * tw + tx] = mx;
      }
    }
    final out = BitMask(w, h);
    for (var ty = 0; ty < th; ty++) {
      for (var tx = 0; tx < tw; tx++) {
        final mn = nMin[ty * tw + tx], mx = nMax[ty * tw + tx];
        if (mx - mn < params.minContrast) continue;
        final thr = (mn + mx) ~/ 2;
        for (var dy = 0; dy < t; dy++) {
          var k = (ty * t + dy) * w + tx * t;
          for (var dx = 0; dx < t; dx++) {
            if (gray.data[k] < thr) out.data[k] = 1;
            k++;
          }
        }
      }
    }
    return out;
  }

  /// Cuadrilátero inicial a partir de la envolvente: punto más lejano del
  /// centroide, su opuesto, y los extremos a cada lado de esa diagonal.
  List<Pt>? _initialQuad(List<Pt> hull) {
    final c = Poly.centroid(hull);
    var i0 = 0;
    var best = -1.0;
    for (var i = 0; i < hull.length; i++) {
      final d = hull[i].distanceTo(c);
      if (d > best) {
        best = d;
        i0 = i;
      }
    }
    final p0 = hull[i0];
    var i2 = 0;
    best = -1.0;
    for (var i = 0; i < hull.length; i++) {
      final d = hull[i].distanceTo(p0);
      if (d > best) {
        best = d;
        i2 = i;
      }
    }
    final p2 = hull[i2];
    final axis = p2 - p0;
    final len = axis.length;
    if (len < 1e-6) return null;
    var maxS = 0.0, minS = 0.0;
    var i1 = -1, i3 = -1;
    for (var i = 0; i < hull.length; i++) {
      final s = axis.cross(hull[i] - p0) / len; // distancia con signo a la diagonal
      if (s > maxS) {
        maxS = s;
        i1 = i;
      }
      if (s < minS) {
        minS = s;
        i3 = i;
      }
    }
    if (i1 < 0 || i3 < 0 || maxS <= 0.5 || minS >= -0.5) return null;
    final q = [p0, hull[i1], p2, hull[i3]];
    final cc = Poly.centroid(q);
    q.sort((a, b) => math.atan2(a.y - cc.y, a.x - cc.x).compareTo(math.atan2(b.y - cc.y, b.x - cc.x)));
    return q;
  }

  /// Refinamiento a resolución completa por máximo gradiente sobre la normal
  /// de cada lado (claro→oscuro hacia adentro) y ajuste de recta.
  List<Pt>? _refineQuadGradient(List<Pt> quad, GrayRaster gray, int f) {
    final searchPx = math.max(2.0, 1.5 * f);
    final cq = Poly.centroid(quad);
    final lines = <(Pt, Pt)>[]; // (punto medio, dirección)
    final n = params.refineSamples;
    for (var k = 0; k < 4; k++) {
      final a = quad[k], b = quad[(k + 1) % 4];
      final ab = b - a;
      final len = ab.length;
      if (len < 4) return null;
      final d = ab * (1 / len);
      var nrm = d.perp;
      if (nrm.dot(cq - a) > 0) nrm = nrm * -1; // normal hacia AFUERA
      final pts = <Pt>[];
      for (var i = 0; i < n; i++) {
        final t = 0.1 + 0.8 * i / (n - 1);
        final p = a + ab * t;
        double? bestGrad;
        var bestS = 0.0;
        for (var s = -searchPx; s <= searchPx; s += 0.5) {
          final q = p + nrm * s;
          final x = q.x - 0.5, y = q.y - 0.5;
          if (x < 1 || y < 1 || x >= gray.width - 2 || y >= gray.height - 2) break;
          final gp = gray.bilinear(x + nrm.x, y + nrm.y);
          final gm = gray.bilinear(x - nrm.x, y - nrm.y);
          final grad = (gp - gm) / 2; // > 0: más claro hacia afuera
          if (bestGrad == null || grad > bestGrad) {
            bestGrad = grad;
            bestS = s;
          }
        }
        if (bestGrad != null && bestGrad > 4) pts.add(p + nrm * bestS);
      }
      if (pts.length < 4) return null;
      final line = _fitLine(pts);
      if (line == null) return null;
      lines.add(line);
    }
    final out = <Pt>[];
    for (var k = 0; k < 4; k++) {
      final (m1, d1) = lines[(k + 3) % 4];
      final (m2, d2) = lines[k];
      final p = _intersectLines(m1, d1, m2, d2);
      if (p == null) return null;
      out.add(p);
    }
    return out;
  }

  /// Ajuste de recta por PCA 2D: devuelve (media, dirección unitaria).
  static (Pt, Pt)? _fitLine(List<Pt> pts) {
    final m = Poly.centroid(pts);
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (final p in pts) {
      final dx = p.x - m.x, dy = p.y - m.y;
      sxx += dx * dx;
      sxy += dx * dy;
      syy += dy * dy;
    }
    // Vector propio del mayor valor propio de [[sxx,sxy],[sxy,syy]].
    final tr = sxx + syy, det = sxx * syy - sxy * sxy;
    final disc = math.sqrt(math.max(0, tr * tr / 4 - det));
    final l1 = tr / 2 + disc;
    Pt dir;
    if (sxy.abs() > 1e-9) {
      dir = Pt(l1 - syy, sxy);
    } else {
      dir = sxx >= syy ? const Pt(1, 0) : const Pt(0, 1);
    }
    if (dir.length < 1e-9) return null;
    return (m, dir.normalized);
  }

  static Pt? _intersectLines(Pt m1, Pt d1, Pt m2, Pt d2) {
    final den = d1.cross(d2);
    if (den.abs() < 1e-9) return null;
    final t = (m2 - m1).cross(d2) / den;
    return m1 + d1 * t;
  }

  /// Promedio de 3×3 muestras alrededor del centro de la celda (coords de tag,
  /// 0..8) mapeadas a la imagen por [h].
  static double _sampleCell(GrayRaster gray, Homography h, double cx, double cy) {
    var acc = 0.0;
    for (final dy in const [-0.15, 0.0, 0.15]) {
      for (final dx in const [-0.15, 0.0, 0.15]) {
        final p = h.apply(Pt(cx + dx, cy + dy));
        acc += gray.bilinear(p.x - 0.5, p.y - 0.5);
      }
    }
    return acc / 9.0;
  }

  _Decoded? _decode(GrayRaster gray, List<Pt> quad) {
    const unit = [Pt(0, 0), Pt(8, 0), Pt(8, 8), Pt(0, 8)];
    final h = Homography.fromFourPoints(unit, quad);
    if (h == null) return null;
    // Referencias: borde negro (anillo de celdas 0 y 7) y blanco exterior (−1 y 8).
    var bSum = 0.0;
    var bN = 0;
    final outside = <double>[];
    for (var i = 0; i < 8; i++) {
      for (final c in [(i + 0.5, 0.5), (i + 0.5, 7.5), (0.5, i + 0.5), (7.5, i + 0.5)]) {
        bSum += _sampleCell(gray, h, c.$1, c.$2);
        bN++;
      }
    }
    for (var i = -1; i < 9; i++) {
      for (final c in [(i + 0.5, -0.5), (i + 0.5, 8.5), (-0.5, i + 0.5), (8.5, i + 0.5)]) {
        outside.add(_sampleCell(gray, h, c.$1, c.$2));
      }
    }
    outside.sort();
    final bMean = bSum / bN;
    final wMed = outside[outside.length ~/ 2];
    if (wMed - bMean < params.minDecodeContrast) return null;
    final thr = (bMean + wMed) / 2;
    // Rejilla 6×6 de datos (fila-mayor).
    var bits = Uint8List(36);
    for (var r = 0; r < 6; r++) {
      for (var c = 0; c < 6; c++) {
        bits[r * 6 + c] = _sampleCell(gray, h, c + 1.5, r + 1.5) > thr ? 1 : 0;
      }
    }
    int? bestId;
    var bestHam = params.maxHamming + 1;
    var bestRot = 0;
    for (var rot = 0; rot < 4; rot++) {
      for (var id = 0; id < _codeBits.length; id++) {
        final code = _codeBits[id];
        var ham = 0;
        for (var k = 0; k < 36 && ham < bestHam; k++) {
          if (bits[k] != code[k]) ham++;
        }
        if (ham < bestHam) {
          bestHam = ham;
          bestId = id;
          bestRot = rot;
        }
      }
      bits = _rotate90(bits);
    }
    if (bestId == null) return null;
    return _Decoded(bestId, bestHam, bestRot, h);
  }

  /// Rota la rejilla 6×6 90° en sentido horario.
  static Uint8List _rotate90(Uint8List m) {
    final out = Uint8List(36);
    for (var r = 0; r < 6; r++) {
      for (var c = 0; c < 6; c++) {
        out[c * 6 + (5 - r)] = m[r * 6 + c];
      }
    }
    return out;
  }
}

class _Decoded {
  final int id;
  final int hamming;
  final int rotation;
  final Homography h;
  const _Decoded(this.id, this.hamming, this.rotation, this.h);
}
