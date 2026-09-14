import 'dart:math' as math;

/// Punto 2D en coma flotante (píxeles o milímetros según el contexto).
class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double k) => Pt(x * k, y * k);
  double dot(Pt o) => x * o.x + y * o.y;
  double cross(Pt o) => x * o.y - y * o.x;
  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Pt o) => (this - o).length;
  Pt get normalized {
    final l = length;
    return l < 1e-12 ? this : Pt(x / l, y / l);
  }

  /// Normal a la izquierda (rotación +90° en coordenadas de imagen, y hacia abajo).
  Pt get perp => Pt(-y, x);

  Map<String, double> toJson() => {'x': x, 'y': y};
  factory Pt.fromJson(Map<String, dynamic> j) =>
      Pt((j['x'] as num).toDouble(), (j['y'] as num).toDouble());

  @override
  String toString() => 'Pt(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// Rectángulo axis-aligned (x0,y0 incluidos; x1,y1 exclusivos cuando son enteros).
class RectD {
  final double x0, y0, x1, y1;
  const RectD(this.x0, this.y0, this.x1, this.y1);
  double get width => x1 - x0;
  double get height => y1 - y0;
  Pt get center => Pt((x0 + x1) / 2, (y0 + y1) / 2);
  bool contains(Pt p) => p.x >= x0 && p.x < x1 && p.y >= y0 && p.y < y1;

  RectD intersect(RectD o) => RectD(
        math.max(x0, o.x0),
        math.max(y0, o.y0),
        math.min(x1, o.x1),
        math.min(y1, o.y1),
      );

  bool get isEmpty => width <= 0 || height <= 0;

  Map<String, double> toJson() => {'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1};
  factory RectD.fromJson(Map<String, dynamic> j) => RectD(
        (j['x0'] as num).toDouble(),
        (j['y0'] as num).toDouble(),
        (j['x1'] as num).toDouble(),
        (j['y1'] as num).toDouble(),
      );
}

/// Homografía 3×3 (fila-mayor, 9 valores). Mapea puntos homogéneos: p' ~ H·p.
class Homography {
  final List<double> m; // 9 valores, fila-mayor
  const Homography(this.m);

  static const Homography identity = Homography([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  /// Escala uniforme + traslación: (x, y) → (x·s + tx, y·s + ty).
  factory Homography.scaleTranslate(double s, double tx, double ty) =>
      Homography([s, 0, tx, 0, s, ty, 0, 0, 1]);

  Pt apply(Pt p) {
    final w = m[6] * p.x + m[7] * p.y + m[8];
    final iw = w.abs() < 1e-12 ? 0.0 : 1.0 / w;
    return Pt(
      (m[0] * p.x + m[1] * p.y + m[2]) * iw,
      (m[3] * p.x + m[4] * p.y + m[5]) * iw,
    );
  }

  /// Composición: (this ∘ other)(p) = this(other(p)).
  Homography compose(Homography o) {
    final a = m, b = o.m;
    final r = List<double>.filled(9, 0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        r[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
      }
    }
    return Homography(r);
  }

  Homography? get inverse {
    final a = m;
    final det = a[0] * (a[4] * a[8] - a[5] * a[7]) -
        a[1] * (a[3] * a[8] - a[5] * a[6]) +
        a[2] * (a[3] * a[7] - a[4] * a[6]);
    if (det.abs() < 1e-14) return null;
    final id = 1.0 / det;
    return Homography([
      (a[4] * a[8] - a[5] * a[7]) * id,
      (a[2] * a[7] - a[1] * a[8]) * id,
      (a[1] * a[5] - a[2] * a[4]) * id,
      (a[5] * a[6] - a[3] * a[8]) * id,
      (a[0] * a[8] - a[2] * a[6]) * id,
      (a[2] * a[3] - a[0] * a[5]) * id,
      (a[3] * a[7] - a[4] * a[6]) * id,
      (a[1] * a[6] - a[0] * a[7]) * id,
      (a[0] * a[4] - a[1] * a[3]) * id,
    ]);
  }

  /// DLT con exactamente 4 correspondencias (src[i] → dst[i]); h33 = 1.
  /// Devuelve null si el sistema es singular (puntos colineales/repetidos).
  static Homography? fromFourPoints(List<Pt> src, List<Pt> dst) {
    assert(src.length == 4 && dst.length == 4);
    // Sistema 8×8: A·h = b
    final a = List<List<double>>.generate(8, (_) => List<double>.filled(8, 0));
    final b = List<double>.filled(8, 0);
    for (var i = 0; i < 4; i++) {
      final x = src[i].x, y = src[i].y, u = dst[i].x, v = dst[i].y;
      a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y];
      b[2 * i] = u;
      a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y];
      b[2 * i + 1] = v;
    }
    final h = solveLinear(a, b);
    if (h == null) return null;
    return Homography([...h, 1.0]);
  }

  List<double> toJson() => List<double>.from(m);
}

/// Resuelve A·x = b por eliminación gaussiana con pivoteo parcial. null si singular.
List<double>? solveLinear(List<List<double>> a, List<double> b) {
  final n = b.length;
  final m = [for (var i = 0; i < n; i++) [...a[i], b[i]]];
  for (var col = 0; col < n; col++) {
    var piv = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[piv][col].abs()) piv = r;
    }
    if (m[piv][col].abs() < 1e-12) return null;
    if (piv != col) {
      final t = m[piv];
      m[piv] = m[col];
      m[col] = t;
    }
    final p = m[col][col];
    for (var r = col + 1; r < n; r++) {
      final f = m[r][col] / p;
      if (f == 0) continue;
      for (var c = col; c <= n; c++) {
        m[r][c] -= f * m[col][c];
      }
    }
  }
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var s = m[i][n];
    for (var c = i + 1; c < n; c++) {
      s -= m[i][c] * x[c];
    }
    x[i] = s / m[i][i];
  }
  return x;
}

/// Utilidades de polígonos.
class Poly {
  const Poly._();

  /// Área con signo (shoelace); positiva en sentido horario en coords de imagen.
  static double signedArea(List<Pt> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      s += a.x * b.y - b.x * a.y;
    }
    return s / 2;
  }

  static double area(List<Pt> p) => signedArea(p).abs();

  static double perimeter(List<Pt> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      s += p[i].distanceTo(p[(i + 1) % p.length]);
    }
    return s;
  }

  static Pt centroid(List<Pt> p) {
    if (p.isEmpty) return const Pt(0, 0);
    var sx = 0.0, sy = 0.0;
    for (final q in p) {
      sx += q.x;
      sy += q.y;
    }
    return Pt(sx / p.length, sy / p.length);
  }

  /// Envolvente convexa (Andrew, cadena monótona). Sin puntos colineales.
  static List<Pt> convexHull(List<Pt> pts) {
    if (pts.length <= 2) return List<Pt>.from(pts);
    final p = List<Pt>.from(pts)
      ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    // eliminar duplicados
    final u = <Pt>[];
    for (final q in p) {
      if (u.isEmpty || u.last.x != q.x || u.last.y != q.y) u.add(q);
    }
    if (u.length <= 2) return u;
    double cross(Pt o, Pt a, Pt b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    // Tolerancia: puntos casi colineales (ruido de coma flotante) no entran.
    const eps = 1e-9;
    final lower = <Pt>[];
    for (final q in u) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= eps) {
        lower.removeLast();
      }
      lower.add(q);
    }
    final upper = <Pt>[];
    for (var i = u.length - 1; i >= 0; i--) {
      final q = u[i];
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= eps) {
        upper.removeLast();
      }
      upper.add(q);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// Diámetro de Feret máximo (par de puntos más lejanos) sobre la envolvente.
  /// Devuelve (a, b, distancia).
  static (Pt, Pt, double) maxFeret(List<Pt> hull) {
    if (hull.isEmpty) return (const Pt(0, 0), const Pt(0, 0), 0);
    var best = 0.0;
    var ia = 0, ib = 0;
    for (var i = 0; i < hull.length; i++) {
      for (var j = i + 1; j < hull.length; j++) {
        final d = hull[i].distanceTo(hull[j]);
        if (d > best) {
          best = d;
          ia = i;
          ib = j;
        }
      }
    }
    return (hull[ia], hull[ib], best);
  }

  /// Extensión de los puntos proyectados sobre la dirección [dir] (unitaria).
  static (double, double) extentAlong(List<Pt> pts, Pt dir) {
    var mn = double.infinity, mx = -double.infinity;
    for (final p in pts) {
      final t = p.dot(dir);
      if (t < mn) mn = t;
      if (t > mx) mx = t;
    }
    return (mn, mx);
  }

  /// Simplificación Douglas–Peucker de un polígono CERRADO (epsilon en px).
  static List<Pt> simplifyClosed(List<Pt> poly, double epsilon) {
    if (poly.length < 4) return List<Pt>.from(poly);
    // Partir en dos cadenas por los puntos más lejanos entre sí para cerrar bien.
    var ia = 0, ib = 0;
    var best = -1.0;
    for (var i = 0; i < poly.length; i++) {
      final d = poly[i].distanceTo(poly[(i + poly.length ~/ 2) % poly.length]);
      if (d > best) {
        best = d;
        ia = i;
        ib = (i + poly.length ~/ 2) % poly.length;
      }
    }
    final lo = math.min(ia, ib), hi = math.max(ia, ib);
    final chain1 = poly.sublist(lo, hi + 1);
    final chain2 = [...poly.sublist(hi), ...poly.sublist(0, lo + 1)];
    final s1 = _dp(chain1, epsilon);
    final s2 = _dp(chain2, epsilon);
    // s1 termina en poly[hi] y s2 empieza en poly[hi]; s2 termina en poly[lo] = inicio de s1.
    return [...s1.sublist(0, s1.length - 1), ...s2.sublist(0, s2.length - 1)];
  }

  static List<Pt> _dp(List<Pt> pts, double eps) {
    if (pts.length < 3) return List<Pt>.from(pts);
    final a = pts.first, b = pts.last;
    var maxD = -1.0;
    var idx = 0;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _pointSegmentDistance(pts[i], a, b);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > eps) {
      final left = _dp(pts.sublist(0, idx + 1), eps);
      final right = _dp(pts.sublist(idx), eps);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  static double _pointSegmentDistance(Pt p, Pt a, Pt b) {
    final ab = b - a;
    final l2 = ab.dot(ab);
    if (l2 < 1e-12) return p.distanceTo(a);
    var t = (p - a).dot(ab) / l2;
    t = t.clamp(0.0, 1.0);
    return p.distanceTo(a + ab * t);
  }

  static bool isConvexQuad(List<Pt> q) {
    if (q.length != 4) return false;
    double? sign;
    for (var k = 0; k < 4; k++) {
      final a = q[k], b = q[(k + 1) % 4], c = q[(k + 2) % 4];
      final cr = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cr.abs() < 1e-9) return false;
      final s = cr > 0 ? 1.0 : -1.0;
      if (sign == null) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }
}
