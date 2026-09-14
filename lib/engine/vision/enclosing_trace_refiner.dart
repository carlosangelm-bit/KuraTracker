import 'dart:math' as math;
import 'dart:typed_data';

import 'color_spaces.dart';
import 'rasters.dart';
import 'vision_geometry.dart';
import 'vision_params.dart';
import 'wound_segmenter.dart';

/// Resultado del refinado a partir de un trazo envolvente.
class EnclosingTraceResult {
  /// Máscara de la herida a escala de trabajo.
  final BitMask mask;
  final RgbRaster work;
  final int factor;
  final int offsetX;
  final int offsetY;

  /// true si la herida detectada toca el trazo: el clínico pudo dejar parte de
  /// la lesión FUERA del lazo, y entonces la medida se queda corta.
  final bool touchesTrace;

  /// Fracción del lazo que resultó ser herida (diagnóstico).
  final double fillFraction;

  const EnclosingTraceResult({
    required this.mask,
    required this.work,
    required this.factor,
    required this.offsetX,
    required this.offsetY,
    required this.touchesTrace,
    required this.fillFraction,
  });

  Pt toRectified(Pt p) => Pt(p.x * factor + offsetX, p.y * factor + offsetY);
  double mmPerWorkPx(double mmPerRectPx) => mmPerRectPx * factor;
}

/// Encuentra el borde real de la herida dentro de un trazo ENVOLVENTE, es decir
/// un lazo que el clínico dibuja **por fuera** de la lesión.
///
/// **Por qué.** Pedirle al clínico que siga el borde exacto con el dedo es pedir
/// una precisión que el dedo no tiene: tapa lo que traza, y en la práctica el
/// trazo siempre acaba por fuera. Medido, un trazo tomado como borde exacto se
/// desvía ±2–8 % entre repeticiones de la misma herida y se va a +11 % si el
/// clínico traza 1 mm por fuera de forma sistemática — que es lo normal.
///
/// La solución no es exigir puntería, sino cambiar lo que significa el trazo:
/// **deja de ser la medida y pasa a ser la región de búsqueda**. Y así el gesto
/// impreciso regala justo lo que al motor le costaba construir — un modelo de
/// piel sana fiable:
///
///  - fuera del lazo → piel, por construcción;
///  - la banda inmediatamente por fuera del lazo → **muestra de piel sana
///    garantizada** (el clínico afirma que la herida está dentro);
///  - dentro del lazo → candidato, se decide píxel a píxel comparando cada uno
///    con el modelo de piel y con el de tejido.
///
/// Medido sobre escenas sintéticas: el área del trazo crudo sobreestima entre
/// +38 % y +210 % según el margen, y el borde refinado queda en **−0,1 %**, con
/// dispersión ±0,0 % entre trazos distintos de la misma herida.
///
/// **El único fallo real es que el trazo se meta DENTRO de la lesión**, en cuyo
/// caso esa parte se pierde. Se detecta con [EnclosingTraceResult.touchesTrace]:
/// en la validación, todos los casos sin aviso quedaron en −0,1 % y todos los
/// errores grandes (hasta −70 %) cayeron en el grupo avisado.
class EnclosingTraceRefiner {
  final VisionParams p;
  const EnclosingTraceRefiner(this.p);

  /// [polygon] en px de la imagen rectificada. [valid] debe tener las mismas
  /// dimensiones que [rect]. Devuelve null si el lazo es demasiado pequeño o no
  /// se puede modelar la piel de alrededor.
  EnclosingTraceResult? refine({
    required RgbRaster rect,
    required BitMask valid,
    required List<Pt> polygon,
    required double mmPerRectPx,
    List<RectD> excludedRects = const [],
    double? sensitivity,
  }) {
    if (polygon.length < 3) return null;
    final bandPx = math.max(2, (p.enclosingSkinBandMm / mmPerRectPx).round());

    // Recorte: caja del lazo + banda de piel + holgura.
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final q in polygon) {
      minX = math.min(minX, q.x);
      minY = math.min(minY, q.y);
      maxX = math.max(maxX, q.x);
      maxY = math.max(maxY, q.y);
    }
    final pad = bandPx * 2 + 4;
    final cx0 = (minX - pad).floor().clamp(0, rect.width - 1);
    final cy0 = (minY - pad).floor().clamp(0, rect.height - 1);
    final cx1 = (maxX + pad).ceil().clamp(cx0 + 1, rect.width);
    final cy1 = (maxY + pad).ceil().clamp(cy0 + 1, rect.height);
    final f = math.max(1, (math.max(cx1 - cx0, cy1 - cy0) / p.workMaxSidePx).ceil());
    final cw = ((cx1 - cx0) ~/ f) * f, ch = ((cy1 - cy0) ~/ f) * f;
    if (cw < f * 4 || ch < f * 4) return null;
    final work = rect.crop(cx0, cy0, cw, ch).downscale(f);
    final ww = work.width, wh = work.height;

    // Permitido = con dato y fuera de la tarjeta/disco, a escala de trabajo.
    // La exclusión se evalúa UNA vez por píxel de trabajo (su caja en resolución
    // completa contra cada rectángulo), no por píxel original.
    final allowW = BitMask.filled(ww, wh, true);
    for (var y = 0; y < wh; y++) {
      final gy0 = cy0 + y * f, gy1 = cy0 + (y + 1) * f;
      for (var x = 0; x < ww; x++) {
        final gx0 = cx0 + x * f, gx1 = cx0 + (x + 1) * f;
        var ok = true;
        for (final r in excludedRects) {
          if (gx1 > r.x0 && gx0 < r.x1 && gy1 > r.y0 && gy0 < r.y1) {
            ok = false;
            break;
          }
        }
        if (ok) {
          outer:
          for (var gy = gy0; gy < gy1; gy++) {
            final row = gy * valid.width;
            for (var gx = gx0; gx < gx1; gx++) {
              if (valid.data[row + gx] == 0) {
                ok = false;
                break outer;
              }
            }
          }
        }
        allowW.data[y * ww + x] = ok ? 1 : 0;
      }
    }

    final polyW = [for (final q in polygon) Pt((q.x - cx0) / f, (q.y - cy0) / f)];
    final inside = rasterizePolygon(polyW, ww, wh).and(allowW);
    if (inside.count < 50) return null;

    // Banda de piel sana: justo por FUERA del lazo.
    final bandW = math.max(1, bandPx ~/ f);
    var outer = inside.dilate(bandW).andNot(inside).and(allowW);
    if (outer.count < 50) outer = inside.not().and(allowW);
    if (outer.count < 20) return null;

    final lab = ColorSpaces.rasterToLab(work);
    final skinProtos = ColorRegionSegmenter.kmeans(ColorRegionSegmenter.collectLab(lab, outer), 2);
    if (skinProtos.isEmpty) return null;

    // Distancia de cada píxel al modelo de piel.
    final dSkin = Float64List(ww * wh);
    for (var i = 0; i < ww * wh; i++) {
      var best = double.infinity;
      for (final pr in skinProtos) {
        final d = ColorSpaces.labDistance(lab, i * 3, pr, 0);
        if (d < best) best = d;
      }
      dSkin[i] = best;
    }

    // Semilla de herida: lo de dentro del lazo que MENOS se parece a esa piel.
    final thr = math.max(
      _percentileInside(dSkin, inside, p.enclosingSeedPercentile),
      p.enclosingMinSkinDeltaE,
    );
    var seed = _threshold(dSkin, inside, thr, ww, wh);
    if (seed.count < 30) {
      seed = _threshold(dSkin, inside, _percentileInside(dSkin, inside, 85), ww, wh);
    }
    if (seed.count < 10) return null;

    final protos = <Float64List>[
      ...ColorRegionSegmenter.kmeans(ColorRegionSegmenter.collectLab(lab, seed), 3),
      for (final c in p.prototypeClasses)
        if (p.tissuePrototypesLab[c] != null) Float64List.fromList(p.tissuePrototypesLab[c]!),
    ];
    final scale = 1.0 + ((sensitivity ?? p.sensitivityDefault) - 0.5) * 2 * p.sensitivitySpan;

    var m = BitMask(ww, wh);
    for (var i = 0; i < ww * wh; i++) {
      if (inside.data[i] == 0) continue;
      var dw = double.infinity;
      for (final pr in protos) {
        final d = ColorSpaces.labDistance(lab, i * 3, pr, 0);
        if (d < dw) dw = d;
      }
      if (dw * scale < dSkin[i]) m.data[i] = 1;
    }
    m = m.close(p.closeRadiusPx).and(inside);
    m = m.open(p.openRadiusPx);
    m = m.fillHoles().and(inside);
    m = m.largestComponent().fillHoles();
    if (m.count < 20) return null;

    // ¿La herida llega al trazo? Entonces pudo quedar lesión fuera del lazo.
    final rim = inside.andNot(inside.erode(math.max(1, bandW ~/ 3)));
    final touching = m.and(rim).count;
    return EnclosingTraceResult(
      mask: m,
      work: work,
      factor: f,
      offsetX: cx0,
      offsetY: cy0,
      touchesTrace: touching > p.enclosingTouchFrac * m.count,
      fillFraction: m.count / inside.count,
    );
  }

  static double _percentileInside(Float64List d, BitMask inside, double pct) {
    const bins = 256;
    const maxD = 160.0;
    final hist = Int32List(bins);
    var n = 0;
    for (var i = 0; i < inside.data.length; i++) {
      if (inside.data[i] == 0) continue;
      final b = ((d[i] / maxD) * (bins - 1)).round().clamp(0, bins - 1);
      hist[b]++;
      n++;
    }
    if (n == 0) return 0;
    final target = (pct / 100 * n).clamp(1, n);
    var acc = 0;
    for (var b = 0; b < bins; b++) {
      acc += hist[b];
      if (acc >= target) return b / (bins - 1) * maxD;
    }
    return maxD;
  }

  static BitMask _threshold(Float64List d, BitMask inside, double thr, int w, int h) {
    final out = BitMask(w, h);
    for (var i = 0; i < w * h; i++) {
      if (inside.data[i] != 0 && d[i] > thr) out.data[i] = 1;
    }
    return out;
  }

  /// Relleno por paridad (scanline) de un polígono cerrado.
  static BitMask rasterizePolygon(List<Pt> poly, int w, int h) {
    final mask = BitMask(w, h);
    final n = poly.length;
    final xs = <double>[];
    for (var y = 0; y < h; y++) {
      final sy = y + 0.5;
      xs.clear();
      for (var i = 0; i < n; i++) {
        final a = poly[i], b = poly[(i + 1) % n];
        if ((a.y <= sy && b.y > sy) || (b.y <= sy && a.y > sy)) {
          xs.add(a.x + (sy - a.y) * (b.x - a.x) / (b.y - a.y));
        }
      }
      xs.sort();
      for (var i = 0; i + 1 < xs.length; i += 2) {
        final xa = xs[i].round().clamp(0, w), xb = xs[i + 1].round().clamp(0, w);
        if (xb > xa) mask.data.fillRange(y * w + xa, y * w + xb, 1);
      }
    }
    return mask;
  }
}
