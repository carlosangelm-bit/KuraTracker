// Generador de escenas sintéticas para probar el motor de visión sin hardware.
//
// Espejo del generador Python usado para validar el algoritmo: renderiza en
// un lienzo MÉTRICO (px/mm fijo) la tarjeta WoundCalibrate (4 AprilTags reales
// + disco de 12,7 mm), una herida elíptica con parches de tejido de fracción
// conocida, y luego aplica una perspectiva de cámara conocida. Como conocemos
// la verdad geométrica, medimos el error de toda la cadena.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kuratracker/engine/vision/rasters.dart';
import 'package:kuratracker/engine/vision/tag36h11_table.dart';
import 'package:kuratracker/engine/vision/vision_geometry.dart';
import 'package:kuratracker/engine/vision/vision_params.dart';

class SceneColors {
  static const skin = [222, 178, 150];
  static const granulacion = [168, 48, 44];
  static const esfacelo = [214, 178, 92];
  static const necrosis = [38, 30, 28];
  static const epitelizacion = [232, 170, 178];
  static const white = [245, 245, 245];
  static const discGreen = [40, 190, 70];
  static const drape = [90, 95, 100];
}

class SceneTruth {
  final double areaMm2; // por conteo de píxeles del lienzo
  final double lengthMm;
  final double widthMm;
  final double perimeterMm;
  final double granPct, sloughPct, necroPct;
  final double pxPerMm;
  final Pt woundCenterMm;
  const SceneTruth({
    required this.areaMm2,
    required this.lengthMm,
    required this.widthMm,
    required this.perimeterMm,
    required this.granPct,
    required this.sloughPct,
    required this.necroPct,
    required this.pxPerMm,
    required this.woundCenterMm,
  });
}

CardSpec loadTestCardSpec() => CardSpec.fromJson(
    (jsonDecode(File('assets/engine/vision/card_spec.json').readAsStringSync()) as Map).cast<String, dynamic>());

String loadTestVisionParamsJson() =>
    File('assets/engine/vision/vision_params.json').readAsStringSync();

VisionParams loadTestVisionParams() => VisionParams.fromJsonString(loadTestVisionParamsJson());

/// Bitmap 8×8 del tag (1 = blanco), con borde negro. Misma convención que la tabla.
List<List<int>> tagBitmap(int id) {
  final hex = kTag36h11CodesHex[id];
  final bits = <int>[];
  for (var i = 0; i < hex.length; i++) {
    final v = int.parse(hex[i], radix: 16);
    for (var b = 3; b >= 0; b--) {
      if (bits.length < 36) bits.add((v >> b) & 1);
    }
  }
  final m = List.generate(8, (_) => List.filled(8, 0));
  for (var r = 0; r < 6; r++) {
    for (var c = 0; c < 6; c++) {
      m[r + 1][c + 1] = bits[r * 6 + c];
    }
  }
  return m;
}

/// Renderiza el lienzo métrico. La tarjeta ocupa el origen (0,0) mm.
(RgbRaster, SceneTruth) renderScene(
  CardSpec spec, {
  double pxPerMm = 8.0,
  double woundA = 20.0, // semieje mayor (mm)
  double woundB = 12.0, // semieje menor (mm)
  Pt woundCenterMm = const Pt(140, 30),
  double woundAngleDeg = 20.0,
  double sloughFrac = 0.30,
  double necroFrac = 0.10,
  bool discFallback = false,
  double discDiameterMm = 19.0,
  double fieldWmm = 200.0,
  double fieldHmm = 90.0,
  bool epithelialRim = false,
}) {
  final w = (fieldWmm * pxPerMm).round(), h = (fieldHmm * pxPerMm).round();
  final img = RgbRaster(w, h);
  for (var i = 0; i < w * h; i++) {
    img.data[i * 3] = SceneColors.skin[0];
    img.data[i * 3 + 1] = SceneColors.skin[1];
    img.data[i * 3 + 2] = SceneColors.skin[2];
  }
  void fill(bool Function(double mmX, double mmY) inside, List<int> c) {
    for (var y = 0; y < h; y++) {
      final my = (y + 0.5) / pxPerMm;
      for (var x = 0; x < w; x++) {
        final mx = (x + 0.5) / pxPerMm;
        if (inside(mx, my)) img.set(x, y, c[0], c[1], c[2]);
      }
    }
  }

  if (!discFallback) {
    fill((mx, my) => mx < spec.widthMm && my < spec.heightMm, SceneColors.white);
    for (final t in spec.tags) {
      final bmp = tagBitmap(t.id);
      final cell = t.sizeMm / 8;
      final x0 = t.centerMm.x - t.sizeMm / 2, y0 = t.centerMm.y - t.sizeMm / 2;
      fill((mx, my) {
        if (mx < x0 || my < y0 || mx >= x0 + t.sizeMm || my >= y0 + t.sizeMm) return false;
        return true;
      }, const [8, 8, 8]);
      fill((mx, my) {
        if (mx < x0 || my < y0 || mx >= x0 + t.sizeMm || my >= y0 + t.sizeMm) return false;
        final c = ((mx - x0) / cell).floor().clamp(0, 7), r = ((my - y0) / cell).floor().clamp(0, 7);
        return bmp[r][c] == 1;
      }, const [250, 250, 250]);
    }
    final rc = spec.circleCenterMm, rad = spec.circleDiameterMm / 2;
    fill((mx, my) => math.pow(mx - rc.x, 2) + math.pow(my - rc.y, 2) <= rad * rad, const [15, 15, 15]);
  } else {
    final rad = discDiameterMm / 2;
    fill((mx, my) => math.pow(mx - 40, 2) + math.pow(my - 30, 2) <= rad * rad, SceneColors.discGreen);
  }

  // Herida elíptica rotada.
  final th = woundAngleDeg * math.pi / 180;
  final cosT = math.cos(th), sinT = math.sin(th);
  (double, double) uv(double mx, double my) {
    final dx = mx - woundCenterMm.x, dy = my - woundCenterMm.y;
    return (dx * cosT + dy * sinT, -dx * sinT + dy * cosT);
  }
  bool inside(double mx, double my, double a, double b) {
    final (u, v) = uv(mx, my);
    return (u / a) * (u / a) + (v / b) * (v / b) <= 1.0;
  }
  if (epithelialRim) {
    fill((mx, my) => inside(mx, my, woundA + 3, woundB + 3), SceneColors.epitelizacion);
  }
  fill((mx, my) => inside(mx, my, woundA, woundB), SceneColors.granulacion);
  // Parches por umbral en u: fracción de área exacta por conteo.
  final us = <double>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final mx = (x + 0.5) / pxPerMm, my = (y + 0.5) / pxPerMm;
      if (inside(mx, my, woundA, woundB)) us.add(uv(mx, my).$1);
    }
  }
  us.sort();
  final n = us.length;
  if (sloughFrac > 0) {
    final thr = us[((1 - sloughFrac) * (n - 1)).round()];
    fill((mx, my) => inside(mx, my, woundA, woundB) && uv(mx, my).$1 >= thr, SceneColors.esfacelo);
  }
  if (necroFrac > 0) {
    final thr = us[(necroFrac * (n - 1)).round()];
    fill((mx, my) => inside(mx, my, woundA, woundB) && uv(mx, my).$1 <= thr, SceneColors.necrosis);
  }
  final a = woundA, b = woundB;
  final truth = SceneTruth(
    areaMm2: n / (pxPerMm * pxPerMm),
    lengthMm: 2 * a,
    widthMm: 2 * b,
    perimeterMm: math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b))),
    granPct: 100 * (1 - sloughFrac - necroFrac),
    sloughPct: 100 * sloughFrac,
    necroPct: 100 * necroFrac,
    pxPerMm: pxPerMm,
    woundCenterMm: woundCenterMm,
  );
  return (img, truth);
}

/// Warp inverso con bilineal (mismo que usa el motor, pero independiente).
RgbRaster warpWith(RgbRaster src, Homography srcToDst, int outW, int outH, List<int> fill) {
  final inv = srcToDst.inverse!;
  final out = RgbRaster(outW, outH);
  final rgb = List<double>.filled(3, 0);
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final p = inv.apply(Pt(x + 0.5, y + 0.5));
      if (src.sampleBilinear(p.x - 0.5, p.y - 0.5, rgb)) {
        out.set(x, y, rgb[0].round(), rgb[1].round(), rgb[2].round());
      } else {
        out.set(x, y, fill[0], fill[1], fill[2]);
      }
    }
  }
  return out;
}

/// "Foto" con perspectiva de cámara. Devuelve (foto, H mm → px de la foto).
(RgbRaster, Homography) perspectivePhoto(
  RgbRaster metric,
  double pxPerMm, {
  int outW = 1600,
  int outH = 1200,
  double tilt = 0.12,
  bool blur = true,
  double noise = 4.0,
  int seed = 7,
}) {
  final w = metric.width.toDouble(), h = metric.height.toDouble();
  final mx = outW * 0.06, my = outH * 0.08;
  final dst = [
    Pt(mx + tilt * outW, my + tilt * outH * 0.5),
    Pt(outW - mx - tilt * outW * 0.4, my + tilt * outH * 0.8),
    Pt(outW - mx + tilt * outW * 0.2, outH - my - tilt * outH * 0.3),
    Pt(mx - tilt * outW * 0.6, outH - my - tilt * outH * 0.6),
  ];
  final src = [const Pt(0, 0), Pt(w, 0), Pt(w, h), Pt(0, h)];
  final hPx = Homography.fromFourPoints(src, dst)!;
  var photo = warpWith(metric, hPx, outW, outH, SceneColors.drape);
  if (blur) photo = _blur3(photo);
  if (noise > 0) photo = _addNoise(photo, noise, seed);
  final hMmToPx = hPx.compose(Homography.scaleTranslate(pxPerMm, 0, 0));
  return (photo, hMmToPx);
}

/// Foto cenital isotrópica (rotación + escala), para el modo disco.
(RgbRaster, Homography) topDownPhoto(RgbRaster metric, double pxPerMm, {double angleDeg = 7, double scale = 0.9}) {
  final w = metric.width.toDouble(), h = metric.height.toDouble();
  final th = angleDeg * math.pi / 180;
  final c = math.cos(th) * scale, s = math.sin(th) * scale;
  final src = [const Pt(0, 0), Pt(w, 0), Pt(w, h), Pt(0, h)];
  var dst = [for (final p in src) Pt(c * p.x - s * p.y, s * p.x + c * p.y)];
  final minX = dst.map((p) => p.x).reduce(math.min), minY = dst.map((p) => p.y).reduce(math.min);
  dst = [for (final p in dst) Pt(p.x - minX + 20, p.y - minY + 20)];
  final outW = (dst.map((p) => p.x).reduce(math.max) + 20).ceil();
  final outH = (dst.map((p) => p.y).reduce(math.max) + 20).ceil();
  final hPx = Homography.fromFourPoints(src, dst)!;
  var photo = warpWith(metric, hPx, outW, outH, SceneColors.drape);
  photo = _addNoise(photo, 3.0, 11);
  return (photo, hPx.compose(Homography.scaleTranslate(pxPerMm, 0, 0)));
}

RgbRaster _blur3(RgbRaster src) {
  final w = src.width, h = src.height;
  final tmp = Float64List(w * h * 3);
  final out = RgbRaster(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final xm = math.max(0, x - 1), xp = math.min(w - 1, x + 1);
      for (var c = 0; c < 3; c++) {
        tmp[(y * w + x) * 3 + c] = (src.data[(y * w + xm) * 3 + c] +
                2 * src.data[(y * w + x) * 3 + c] +
                src.data[(y * w + xp) * 3 + c]) /
            4.0;
      }
    }
  }
  for (var y = 0; y < h; y++) {
    final ym = math.max(0, y - 1), yp = math.min(h - 1, y + 1);
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        final v = (tmp[(ym * w + x) * 3 + c] + 2 * tmp[(y * w + x) * 3 + c] + tmp[(yp * w + x) * 3 + c]) / 4.0;
        out.data[(y * w + x) * 3 + c] = v.round().clamp(0, 255);
      }
    }
  }
  return out;
}

RgbRaster _addNoise(RgbRaster src, double sigma, int seed) {
  final rnd = math.Random(seed);
  final out = RgbRaster(src.width, src.height, Uint8List.fromList(src.data));
  for (var i = 0; i < out.data.length; i++) {
    // Aproximación gaussiana: suma de 3 uniformes.
    final g = (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * sigma * 2;
    out.data[i] = (out.data[i] + g).round().clamp(0, 255);
  }
  return out;
}
