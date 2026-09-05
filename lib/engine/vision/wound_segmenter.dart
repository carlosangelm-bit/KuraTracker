import 'dart:math' as math;
import 'dart:typed_data';

import 'color_spaces.dart';
import 'rasters.dart';
import 'vision_geometry.dart';
import 'vision_params.dart';

/// Entrada de la segmentación: imagen rectificada + indicaciones del clínico.
class SegmentationRequest {
  final RgbRaster rectified;
  final BitMask valid; // píxeles con dato
  final List<RectD> excludedRects; // tarjeta / disco
  final List<Pt> seeds; // toques DENTRO de la herida (px rectificados)
  final RectD? roi; // región de búsqueda; null = automática
  final double sensitivity; // 0..1 (0.5 = neutro)

  const SegmentationRequest({
    required this.rectified,
    required this.valid,
    required this.excludedRects,
    required this.seeds,
    this.roi,
    this.sensitivity = 0.5,
  });
}

/// Salida: máscara a escala de trabajo + cómo volver a px rectificados.
class SegmentationResult {
  final BitMask mask; // escala de trabajo (recorte del ROI reducido por [factor])
  final RgbRaster work; // recorte RGB a escala de trabajo (para el clasificador)
  final int factor; // reducción entera rect → work
  final int offsetX; // origen del recorte en px rectificados
  final int offsetY;
  final RectD roi; // ROI efectivo (px rectificados)

  const SegmentationResult({
    required this.mask,
    required this.work,
    required this.factor,
    required this.offsetX,
    required this.offsetY,
    required this.roi,
  });

  /// mm por píxel de la máscara de trabajo dado el mm/px de la rectificada.
  double mmPerWorkPx(double mmPerRectPx) => mmPerRectPx * factor;

  /// Convierte un punto de la máscara de trabajo a px rectificados.
  Pt toRectified(Pt p) => Pt(p.x * factor + offsetX, p.y * factor + offsetY);
}

/// Contrato del segmentador: permite sustituir el método clásico por un modelo
/// aprendido (TFLite/ONNX) sin tocar la UI ni el resto del motor.
abstract class WoundSegmenter {
  SegmentationResult? segment(SegmentationRequest req);
}

/// Segmentador clásico por color (sin dataset), validado sobre escenas
/// sintéticas. Dos etapas:
///  A. crecimiento desde cada semilla por similitud Lab (ΔE < umbral);
///  B. modelo herida-vs-fondo iterativo dentro de un ROI: prototipos de herida
///     (parches semilla + k-means + prototipos de tejido) contra prototipos de
///     fondo (banda exterior del ROI / anillo fuera de la región), con
///     conectividad a las semillas, morfología y relleno de huecos.
class ColorRegionSegmenter implements WoundSegmenter {
  final VisionParams p;
  const ColorRegionSegmenter(this.p);

  @override
  SegmentationResult? segment(SegmentationRequest req) {
    final rect = req.rectified;
    final w = rect.width, h = rect.height;
    final allowed = req.valid.clone();
    for (final r in req.excludedRects) {
      allowed.fillRect(r.x0.floor(), r.y0.floor(), r.x1.ceil(), r.y1.ceil(), false);
    }
    final seeds = <Pt>[
      for (final s in req.seeds)
        if (allowed.inBounds(s.x.floor(), s.y.floor()) && allowed.get(s.x.floor(), s.y.floor())) s
    ];
    if (seeds.isEmpty) return null;

    // ---- Etapa A (a resolución rectificada, pero acotada a una ventana amplia) ----
    final labFull = ColorSpaces.rasterToLab(rect);
    final r = p.seedPatchRadiusPx;
    final seedProtos = <Float64List>[];
    for (final s in seeds) {
      final sx = s.x.floor(), sy = s.y.floor();
      final acc = Float64List(3);
      var n = 0;
      for (var y = math.max(0, sy - r); y <= math.min(h - 1, sy + r); y++) {
        for (var x = math.max(0, sx - r); x <= math.min(w - 1, sx + r); x++) {
          final k = (y * w + x) * 3;
          acc[0] += labFull[k];
          acc[1] += labFull[k + 1];
          acc[2] += labFull[k + 2];
          n++;
        }
      }
      seedProtos.add(Float64List.fromList([acc[0] / n, acc[1] / n, acc[2] / n]));
    }
    final similar = BitMask(w, h);
    for (var i = 0, k = 0; i < w * h; i++, k += 3) {
      if (allowed.data[i] == 0) continue;
      for (final pr in seedProtos) {
        if (ColorSpaces.labDistance(labFull, k, pr, 0) < p.stageADeltaE) {
          similar.data[i] = 1;
          break;
        }
      }
    }
    var regionA = similar.keepComponentsContaining(seeds);
    for (final s in seeds) {
      regionA.fillRect(s.x.floor() - r, s.y.floor() - r, s.x.floor() + r + 1, s.y.floor() + r + 1, true);
    }
    regionA = regionA.and(allowed);

    // ---- ROI ----
    RectD roi;
    if (req.roi != null) {
      roi = req.roi!;
    } else {
      final bb = regionA.boundingBox()!;
      final c = bb.center;
      final hw = bb.width / 2 * (1 + p.roiExpand) + p.roiPadPx;
      final hh = bb.height / 2 * (1 + p.roiExpand) + p.roiPadPx;
      roi = RectD(c.x - hw, c.y - hh, c.x + hw, c.y + hh);
    }
    final rx0 = roi.x0.floor().clamp(0, w), ry0 = roi.y0.floor().clamp(0, h);
    final rx1 = roi.x1.ceil().clamp(0, w), ry1 = roi.y1.ceil().clamp(0, h);
    if (rx1 - rx0 < 4 || ry1 - ry0 < 4) return null;
    roi = RectD(rx0.toDouble(), ry0.toDouble(), rx1.toDouble(), ry1.toDouble());

    // ---- Recorte + escala de trabajo ----
    final f = math.max(1, (math.max(rx1 - rx0, ry1 - ry0) / p.workMaxSidePx).ceil());
    final cw = ((rx1 - rx0) ~/ f) * f, ch = ((ry1 - ry0) ~/ f) * f;
    if (cw < f || ch < f) return null;
    final work = rect.crop(rx0, ry0, cw, ch).downscale(f);
    final ww = work.width, wh = work.height;
    final allowW = BitMask.filled(ww, wh, true);
    final regW = BitMask(ww, wh);
    for (var y = 0; y < wh; y++) {
      for (var x = 0; x < ww; x++) {
        var allOk = true;
        var anyReg = false;
        for (var dy = 0; dy < f && allOk; dy++) {
          for (var dx = 0; dx < f; dx++) {
            final gx = rx0 + x * f + dx, gy = ry0 + y * f + dy;
            if (allowed.data[gy * w + gx] == 0) {
              allOk = false;
              break;
            }
            if (regionA.data[gy * w + gx] != 0) anyReg = true;
          }
        }
        allowW.data[y * ww + x] = allOk ? 1 : 0;
        regW.data[y * ww + x] = (allOk && anyReg) ? 1 : 0;
      }
    }
    final lab = ColorSpaces.rasterToLab(work);
    final seedsW = <Pt>[
      for (final s in seeds)
        if (((s.x - rx0) ~/ f) >= 0 && ((s.x - rx0) ~/ f) < ww && ((s.y - ry0) ~/ f) >= 0 && ((s.y - ry0) ~/ f) < wh)
          Pt(((s.x - rx0) ~/ f).toDouble(), ((s.y - ry0) ~/ f).toDouble())
    ];
    if (seedsW.isEmpty) return null;

    // ---- Etapa B ----
    var region = regW;
    final scale = 1.0 + (req.sensitivity - 0.5) * 2 * p.sensitivitySpan;
    final tissueProtos = <Float64List>[
      for (final c in p.prototypeClasses)
        if (p.tissuePrototypesLab[c] != null) Float64List.fromList(p.tissuePrototypesLab[c]!)
    ];
    final band = math.max(2, (math.min(ww, wh) * p.roiBandFrac).floor());
    final borderBand = BitMask(ww, wh);
    borderBand.fillRect(0, 0, ww, band, true);
    borderBand.fillRect(0, wh - band, ww, wh, true);
    borderBand.fillRect(0, 0, band, wh, true);
    borderBand.fillRect(ww - band, 0, ww, wh, true);

    final dw = Float64List(ww * wh);
    final ds = Float64List(ww * wh);
    for (var it = 0; it < p.iterations; it++) {
      final regionPts = _collect(lab, region);
      final k = math.min(p.subClusters, math.max(1, regionPts.length ~/ 20));
      final protos = <Float64List>[...seedProtos, ..._kmeans(regionPts, k), ...tissueProtos];
      // Fondo: 1ª iteración = banda exterior del ROI; después, todo lo que queda
      // fuera de la región dilatada (un anillo de ringWidthPx la separa).
      BitMask bgMask = it == 0 ? borderBand.and(allowW).andNot(region) : region.dilate(p.ringWidthPx).not().and(allowW);
      if (bgMask.count < 10) bgMask = region.not().and(allowW);
      final bgProtos = _kmeans(_collect(lab, bgMask), 2);
      if (bgProtos.isEmpty) break;
      for (var i = 0; i < ww * wh; i++) {
        final kk = i * 3;
        var best = double.infinity;
        for (final pr in protos) {
          final d = ColorSpaces.labDistance(lab, kk, pr, 0);
          if (d < best) best = d;
        }
        dw[i] = best;
        best = double.infinity;
        for (final pr in bgProtos) {
          final d = ColorSpaces.labDistance(lab, kk, pr, 0);
          if (d < best) best = d;
        }
        ds[i] = best;
      }
      final woundLike = BitMask(ww, wh);
      for (var i = 0; i < ww * wh; i++) {
        if (allowW.data[i] != 0 && dw[i] * scale < ds[i]) woundLike.data[i] = 1;
      }
      var next = woundLike.keepComponentsContaining(seedsW);
      if (next.count == 0) next = region;
      next = next.close(p.closeRadiusPx).and(allowW);
      next = next.open(p.openRadiusPx);
      next = next.fillHoles().and(allowW);
      final kept = next.keepComponentsContaining(seedsW);
      if (kept.count > 0) next = kept;
      final prevCount = region.count;
      final change = (next.count - prevCount).abs() / math.max(1, prevCount);
      region = next;
      if (change < 0.02 && it > 0) break;
    }
    if (region.count == 0) return null;
    // Una sola herida por medición: si las semillas cayeron en regiones que no
    // se conectaron, se conserva la mayor (área, contorno y tejido coherentes).
    region = region.largestComponent();

    return SegmentationResult(
      mask: region,
      work: work,
      factor: f,
      offsetX: rx0,
      offsetY: ry0,
      roi: roi,
    );
  }

  /// Reúne los valores Lab de los píxeles activos de [mask] (plano).
  static Float64List _collect(Float64List lab, BitMask mask) {
    final n = mask.count;
    final out = Float64List(n * 3);
    var j = 0;
    for (var i = 0; i < mask.data.length; i++) {
      if (mask.data[i] == 0) continue;
      out[j++] = lab[i * 3];
      out[j++] = lab[i * 3 + 1];
      out[j++] = lab[i * 3 + 2];
    }
    return out;
  }

  /// k-means sencillo sobre puntos Lab planos. Inicializa por cuantiles de L*.
  static List<Float64List> _kmeans(Float64List pts, int k, {int iters = 8}) {
    final n = pts.length ~/ 3;
    if (n == 0) return const [];
    if (k <= 1 || n < k) {
      final c = Float64List(3);
      for (var i = 0; i < n; i++) {
        c[0] += pts[i * 3];
        c[1] += pts[i * 3 + 1];
        c[2] += pts[i * 3 + 2];
      }
      return [Float64List.fromList([c[0] / n, c[1] / n, c[2] / n])];
    }
    final order = List<int>.generate(n, (i) => i)..sort((a, b) => pts[a * 3].compareTo(pts[b * 3]));
    final cents = <Float64List>[
      for (var i = 0; i < k; i++)
        Float64List.fromList([
          pts[order[((i + 0.5) * n / k).floor()] * 3],
          pts[order[((i + 0.5) * n / k).floor()] * 3 + 1],
          pts[order[((i + 0.5) * n / k).floor()] * 3 + 2],
        ])
    ];
    final assign = Uint8List(n);
    for (var it = 0; it < iters; it++) {
      for (var i = 0; i < n; i++) {
        var best = double.infinity;
        var bi = 0;
        for (var c = 0; c < k; c++) {
          final d = ColorSpaces.labDistance(pts, i * 3, cents[c], 0);
          if (d < best) {
            best = d;
            bi = c;
          }
        }
        assign[i] = bi;
      }
      final acc = List<Float64List>.generate(k, (_) => Float64List(3));
      final cnt = Int32List(k);
      for (var i = 0; i < n; i++) {
        final c = assign[i];
        acc[c][0] += pts[i * 3];
        acc[c][1] += pts[i * 3 + 1];
        acc[c][2] += pts[i * 3 + 2];
        cnt[c]++;
      }
      for (var c = 0; c < k; c++) {
        if (cnt[c] == 0) continue;
        cents[c] = Float64List.fromList([acc[c][0] / cnt[c], acc[c][1] / cnt[c], acc[c][2] / cnt[c]]);
      }
    }
    return cents;
  }
}
