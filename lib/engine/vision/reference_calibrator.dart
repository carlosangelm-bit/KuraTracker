import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'apriltag_detector.dart';
import 'color_spaces.dart';
import 'rasters.dart';
import 'vision_geometry.dart';
import 'vision_params.dart';
import 'wound_vision_models.dart';

/// Resultado interno de la calibración: además del [CalibrationResult] público,
/// conserva el raster rectificado para no re-decodificar el PNG en el mismo
/// proceso.
class CalibrationOutcome {
  final CalibrationResult? result;
  final RgbRaster? rectified;
  final BitMask? valid; // píxeles con dato (fuera de la foto original → 0)
  final CalibrationFailure? failure;
  const CalibrationOutcome.ok(this.result, this.rectified, this.valid) : failure = null;
  const CalibrationOutcome.fail(this.failure)
      : result = null,
        rectified = null,
        valid = null;
}

/// Convierte píxeles a milímetros a partir de una referencia física:
/// la tarjeta WoundCalibrate (vía principal) o el disco de respaldo.
class ReferenceCalibrator {
  final CardSpec spec;
  final VisionParams params;
  late final AprilTagDetector _detector = AprilTagDetector(params.tagDetector);

  ReferenceCalibrator({required this.spec, required this.params});

  /// Intenta la tarjeta y, si no hay 4 tags, el disco. [preferDisc] fuerza el disco.
  CalibrationOutcome calibrate(RgbRaster photo, {bool preferDisc = false}) {
    if (!preferDisc) {
      final card = calibrateWithCard(photo);
      if (card.result != null) return card;
      final disc = calibrateWithDisc(photo);
      if (disc.result != null) return disc;
      // Preferimos el mensaje de la tarjeta si se vieron tags parciales.
      if ((card.failure?.tagsFound ?? 0) > 0) return card;
      return disc;
    }
    final disc = calibrateWithDisc(photo);
    if (disc.result != null) return disc;
    return calibrateWithCard(photo);
  }

  // ---------------------------------------------------------------------------
  // Tarjeta (AprilTags)
  // ---------------------------------------------------------------------------

  CalibrationOutcome calibrateWithCard(RgbRaster photo) {
    final dets = _detector.detect(photo);
    final byId = {for (final d in dets) d.id: d};
    final missing = [for (final id in spec.tagIds) if (!byId.containsKey(id)) id];
    if (missing.isNotEmpty) {
      final found = spec.tagIds.length - missing.length;
      return CalibrationOutcome.fail(CalibrationFailure(
        found == 0 ? 'no_reference' : 'partial_tags',
        found == 0
            ? 'No se encontró la tarjeta de calibración en la foto.'
            : 'Solo se detectaron $found de ${spec.tagIds.length} marcadores de la tarjeta. '
                'Verifica que esté completa, plana y sin reflejos.',
        tagsFound: found,
      ));
    }
    final src = [for (final t in spec.tags) byId[t.id]!.center];
    final dst = [for (final t in spec.tags) t.centerMm];
    final hPxToMm = Homography.fromFourPoints(src, dst);
    if (hPxToMm == null) {
      return const CalibrationOutcome.fail(
          CalibrationFailure('decode_error', 'No se pudo calcular la geometría de la tarjeta.'));
    }

    // Planaridad: lados de cada tag en mm vs size_mm.
    var planarityErr = 0.0;
    for (final t in spec.tags) {
      final q = byId[t.id]!.corners;
      final qmm = [for (final p in q) hPxToMm.apply(p)];
      for (var k = 0; k < 4; k++) {
        final s = qmm[k].distanceTo(qmm[(k + 1) % 4]);
        planarityErr = math.max(planarityErr, (s - t.sizeMm).abs() / t.sizeMm * 100);
      }
    }

    // Marco métrico: esquinas de la foto → mm, recortado a tarjeta ± margen.
    final w = photo.width.toDouble(), h = photo.height.toDouble();
    final cornersMm = [
      for (final p in [const Pt(0, 0), Pt(w, 0), Pt(w, h), Pt(0, h)]) hPxToMm.apply(p)
    ];
    final m = params.rectifyMaxMarginMm;
    var x0 = -m, y0 = -m, x1 = spec.widthMm + m, y1 = spec.heightMm + m;
    final minX = cornersMm.map((p) => p.x).reduce(math.min);
    final maxX = cornersMm.map((p) => p.x).reduce(math.max);
    final minY = cornersMm.map((p) => p.y).reduce(math.min);
    final maxY = cornersMm.map((p) => p.y).reduce(math.max);
    // Si la proyección es razonable (no explota hacia el horizonte), recortar a la foto.
    if (minX.isFinite && minX > x0) x0 = minX;
    if (minY.isFinite && minY > y0) y0 = minY;
    if (maxX.isFinite && maxX < x1) x1 = maxX;
    if (maxY.isFinite && maxY < y1) y1 = maxY;
    if (x1 - x0 < spec.widthMm || y1 - y0 < spec.heightMm) {
      // Garantizar que la tarjeta completa quede dentro.
      x0 = math.min(x0, 0);
      y0 = math.min(y0, 0);
      x1 = math.max(x1, spec.widthMm);
      y1 = math.max(y1, spec.heightMm);
    }
    var ppm = params.targetPxPerMm;
    final ext = math.max(x1 - x0, y1 - y0);
    ppm = math.min(ppm, params.rectifyMaxSidePx / ext);
    final outW = ((x1 - x0) * ppm).floor(), outH = ((y1 - y0) * ppm).floor();
    if (outW < 16 || outH < 16) {
      return const CalibrationOutcome.fail(
          CalibrationFailure('decode_error', 'La geometría de la tarjeta produce una imagen vacía.'));
    }
    final mmToRect = Homography.scaleTranslate(ppm, -x0 * ppm, -y0 * ppm);
    final photoToRect = mmToRect.compose(hPxToMm);
    final warped = _warp(photo, photoToRect, outW, outH);
    if (warped == null) {
      return const CalibrationOutcome.fail(
          CalibrationFailure('decode_error', 'No se pudo rectificar la imagen.'));
    }
    final (rect, valid) = warped;
    final mmPerPx = 1 / ppm;

    final cardRect = RectD((0 - x0) * ppm, (0 - y0) * ppm, (spec.widthMm - x0) * ppm, (spec.heightMm - y0) * ppm);
    final circleDev = spec.circleCheckMode == 'skip' ? null : _checkCircle(rect, x0, y0, ppm);
    final tagSide = dets.map((d) => d.sidePx).reduce((a, b) => a + b) / dets.length;
    final gates = <QualityGate>[
      QualityGate('tags', 'Marcadores de la tarjeta', GateStatus.pass, '4 de 4 detectados'),
      QualityGate(
        'planarity',
        'Tarjeta plana',
        planarityErr <= params.planarityMaxSideErrorPct ? GateStatus.pass : GateStatus.fail,
        'Error de lado ${planarityErr.toStringAsFixed(1)} % (máx. ${params.planarityMaxSideErrorPct.toStringAsFixed(0)} %)',
      ),
      if (circleDev == null)
        QualityGate('scale_check', 'Verificación de escala', GateStatus.skipped,
            spec.circleCheckMode == 'skip' ? 'Omitida por configuración' : 'Círculo de referencia no localizado')
      else
        QualityGate(
          'scale_check',
          'Verificación de escala',
          circleDev.abs() <= params.circleDiameterTolPct ? GateStatus.pass : GateStatus.fail,
          'Círculo de ${spec.circleDiameterMm} mm: desvío ${circleDev >= 0 ? '+' : ''}${circleDev.toStringAsFixed(1)} %',
        ),
      QualityGate(
        'distance',
        'Distancia de la cámara',
        tagSide >= params.minTagSidePx ? GateStatus.pass : GateStatus.warn,
        tagSide >= params.minTagSidePx
            ? 'Marcadores de ${tagSide.toStringAsFixed(0)} px'
            : 'Marcadores pequeños (${tagSide.toStringAsFixed(0)} px): acércate a la herida',
      ),
      if (spec.isPlaceholder)
        const QualityGate('card_spec', 'Geometría de la tarjeta', GateStatus.warn,
            'card_spec.json es provisional: las medidas no son confiables hasta cargar la geometría del impreso real'),
    ];

    final result = CalibrationResult(
      mode: CalibrationMode.card,
      mmPerPx: mmPerPx,
      width: rect.width,
      height: rect.height,
      rectifiedPng: img.encodePng(rect.toImage(), level: 3),
      excludedRects: [cardRect],
      photoToRectified: photoToRect,
      gates: gates,
      meta: {
        'origin_mm': [x0, y0],
        'px_per_mm': ppm,
        'planarity_err_pct': planarityErr,
        'circle_dev_pct': circleDev,
        'tag_side_px': tagSide,
        'tags': [for (final d in dets) d.toJson()],
        'card_is_placeholder': spec.isPlaceholder,
        'h_photo_to_rect': photoToRect.toJson(),
      },
    );
    return CalibrationOutcome.ok(result, rect, valid);
  }

  /// Warp inverso con muestreo bilineal. Devuelve (raster, máscara de validez).
  (RgbRaster, BitMask)? _warp(RgbRaster src, Homography fwd, int outW, int outH) {
    final inv = fwd.inverse;
    if (inv == null) return null;
    final out = RgbRaster(outW, outH);
    final valid = BitMask(outW, outH);
    final rgb = List<double>.filled(3, 0);
    final m = inv.m;
    var k = 0;
    for (var y = 0; y < outH; y++) {
      final v = y + 0.5;
      for (var x = 0; x < outW; x++) {
        final u = x + 0.5;
        final wq = m[6] * u + m[7] * v + m[8];
        if (wq.abs() < 1e-12) {
          out.data[k] = out.data[k + 1] = out.data[k + 2] = 120;
          k += 3;
          continue;
        }
        final sx = (m[0] * u + m[1] * v + m[2]) / wq - 0.5;
        final sy = (m[3] * u + m[4] * v + m[5]) / wq - 0.5;
        if (src.sampleBilinear(sx, sy, rgb)) {
          out.data[k] = rgb[0].round();
          out.data[k + 1] = rgb[1].round();
          out.data[k + 2] = rgb[2].round();
          valid.data[y * outW + x] = 1;
        } else {
          out.data[k] = out.data[k + 1] = out.data[k + 2] = 120;
        }
        k += 3;
      }
    }
    return (out, valid);
  }

  /// Desvío (%) del diámetro del círculo de referencia medido en la rectificada.
  double? _checkCircle(RgbRaster rect, double x0, double y0, double ppm) {
    final cx = (spec.circleCenterMm.x - x0) * ppm, cy = (spec.circleCenterMm.y - y0) * ppm;
    final dPx = spec.circleDiameterMm * ppm;
    final r = dPx.round();
    final gray = rect.toGray();
    final wx0 = (cx - r).floor().clamp(0, rect.width), wx1 = (cx + r).ceil().clamp(0, rect.width);
    final wy0 = (cy - r).floor().clamp(0, rect.height), wy1 = (cy + r).ceil().clamp(0, rect.height);
    final ww = wx1 - wx0, wh = wy1 - wy0;
    if (ww < 4 || wh < 4) return null;
    var mn = 255, mx = 0;
    for (var y = wy0; y < wy1; y++) {
      for (var x = wx0; x < wx1; x++) {
        final v = gray.at(x, y);
        if (v < mn) mn = v;
        if (v > mx) mx = v;
      }
    }
    if (mx - mn < 40) return null;
    final thr = (mn + mx) / 2;
    final dark = BitMask(ww, wh);
    for (var y = 0; y < wh; y++) {
      for (var x = 0; x < ww; x++) {
        if (gray.at(wx0 + x, wy0 + y) < thr) dark.data[y * ww + x] = 1;
      }
    }
    final (labels, n) = dark.label();
    if (n == 0) return null;
    final lx = (cx - wx0).floor().clamp(0, ww - 1), ly = (cy - wy0).floor().clamp(0, wh - 1);
    var lbl = labels[ly * ww + lx];
    if (lbl == 0) {
      // Componente cuyo centroide esté más cerca del centro esperado.
      final sx = Float64List(n + 1), sy = Float64List(n + 1), cnt = Int32List(n + 1);
      for (var y = 0; y < wh; y++) {
        for (var x = 0; x < ww; x++) {
          final l = labels[y * ww + x];
          if (l == 0) continue;
          sx[l] += x;
          sy[l] += y;
          cnt[l]++;
        }
      }
      var best = double.infinity;
      for (var l = 1; l <= n; l++) {
        final d = math.sqrt(math.pow(sx[l] / cnt[l] - lx, 2) + math.pow(sy[l] / cnt[l] - ly, 2));
        if (d < best) {
          best = d;
          lbl = l;
        }
      }
      if (best > dPx * 0.5) return null;
    }
    var area = 0;
    for (final l in labels) {
      if (l == lbl) area++;
    }
    final dMeas = 2 * math.sqrt(area / math.pi);
    return (dMeas - dPx) / dPx * 100;
  }

  // ---------------------------------------------------------------------------
  // Disco de respaldo
  // ---------------------------------------------------------------------------

  CalibrationOutcome calibrateWithDisc(RgbRaster photo) {
    final h = photo.height, w = photo.width;
    final f = math.max(1, (math.max(h, w) / 1000).ceil());
    final small = photo.downscale(f);
    final hsv = Float64List(3);
    final mask = BitMask(small.width, small.height);
    for (var y = 0, k = 0; y < small.height; y++) {
      for (var x = 0; x < small.width; x++, k += 3) {
        ColorSpaces.rgbToHsv(small.data[k], small.data[k + 1], small.data[k + 2], hsv);
        if (ColorSpaces.hueInRange(hsv[0], params.discHueMin, params.discHueMax) &&
            hsv[1] >= params.discSMin &&
            hsv[2] >= params.discVMin) {
          mask.data[y * small.width + x] = 1;
        }
      }
    }
    final (labels, n) = mask.label();
    final minX = Int32List(n + 1)..fillRange(0, n + 1, small.width);
    final minY = Int32List(n + 1)..fillRange(0, n + 1, small.height);
    final maxX = Int32List(n + 1)..fillRange(0, n + 1, -1);
    final maxY = Int32List(n + 1)..fillRange(0, n + 1, -1);
    final area = Int32List(n + 1);
    for (var y = 0; y < small.height; y++) {
      for (var x = 0; x < small.width; x++) {
        final l = labels[y * small.width + x];
        if (l == 0) continue;
        area[l]++;
        if (x < minX[l]) minX[l] = x;
        if (x > maxX[l]) maxX[l] = x;
        if (y < minY[l]) minY[l] = y;
        if (y > maxY[l]) maxY[l] = y;
      }
    }
    var bestL = 0;
    var bestArea = 0;
    var bestAspect = 0.0;
    for (var l = 1; l <= n; l++) {
      if (area[l] * f * f < params.discMinAreaPx) continue;
      final bw = maxX[l] - minX[l] + 1, bh = maxY[l] - minY[l] + 1;
      final aspect = math.min(bw, bh) / math.max(bw, bh);
      final fill = area[l] / (math.pi * (bw / 2) * (bh / 2));
      if (aspect < params.discAspectMin || fill < params.discFillMin) continue;
      if (area[l] > bestArea) {
        bestArea = area[l];
        bestL = l;
        bestAspect = aspect;
      }
    }
    if (bestL == 0) {
      return const CalibrationOutcome.fail(CalibrationFailure(
        'no_reference',
        'No se encontró ninguna referencia de escala (tarjeta de calibración ni disco de referencia).',
      ));
    }
    final dPxFull = 2 * math.sqrt(bestArea / math.pi) * f;
    var mmPerPx = params.discDiameterMm / dPxFull;

    // "Rectificada" = la foto, reducida por entero si excede el tamaño máximo.
    final fr = math.max(1, (math.max(h, w) / params.rectifyMaxSidePx).ceil());
    final rect = photo.downscale(fr);
    mmPerPx *= fr;
    final discRect = RectD(
      minX[bestL] * f / fr,
      minY[bestL] * f / fr,
      (maxX[bestL] + 1) * f / fr,
      (maxY[bestL] + 1) * f / fr,
    );
    final gates = <QualityGate>[
      const QualityGate('reference', 'Referencia de escala', GateStatus.pass, 'Disco de referencia detectado'),
      QualityGate(
        'disc_tilt',
        'Foto cenital',
        bestAspect >= params.discTiltMinRatio ? GateStatus.pass : GateStatus.fail,
        bestAspect >= params.discTiltMinRatio
            ? 'Disco circular (relación ${bestAspect.toStringAsFixed(2)})'
            : 'El disco se ve ovalado (${bestAspect.toStringAsFixed(2)}): la cámara no está perpendicular',
      ),
      const QualityGate('perspective', 'Corrección de perspectiva', GateStatus.warn,
          'Sin tarjeta no se corrige la perspectiva: la medida asume foto perpendicular a la herida'),
    ];
    final result = CalibrationResult(
      mode: CalibrationMode.disc,
      mmPerPx: mmPerPx,
      width: rect.width,
      height: rect.height,
      rectifiedPng: img.encodePng(rect.toImage(), level: 3),
      excludedRects: [discRect],
      photoToRectified: Homography.scaleTranslate(1 / fr, 0, 0),
      gates: gates,
      meta: {
        'disc_diameter_px_full': dPxFull,
        'disc_aspect': bestAspect,
        'downscale': fr,
        'disc_rect_px': discRect.toJson(),
      },
    );
    return CalibrationOutcome.ok(result, rect, BitMask.filled(rect.width, rect.height, true));
  }
}
