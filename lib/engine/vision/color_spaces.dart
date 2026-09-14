import 'dart:math' as math;
import 'dart:typed_data';

import 'rasters.dart';

/// Conversión de color usada por la segmentación (CIELAB, D65) y por el
/// clasificador de tejido (HSV). Implementación propia para no depender de
/// nada nativo: corre igual en Flutter Web y en móvil.
class ColorSpaces {
  const ColorSpaces._();

  static final Float64List _srgbToLinear = _buildGammaLut();

  static Float64List _buildGammaLut() {
    final lut = Float64List(256);
    for (var i = 0; i < 256; i++) {
      final c = i / 255.0;
      lut[i] = c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }
    return lut;
  }

  static double _labF(double t) =>
      t > 0.008856 ? math.pow(t, 1.0 / 3.0).toDouble() : 7.787 * t + 16.0 / 116.0;

  /// RGB (0–255) → L*a*b*. Escribe en [out] (3 valores).
  static void rgbToLab(int r, int g, int b, Float64List out, [int offset = 0]) {
    final rl = _srgbToLinear[r], gl = _srgbToLinear[g], bl = _srgbToLinear[b];
    final x = (0.4124 * rl + 0.3576 * gl + 0.1805 * bl) / 0.95047;
    final y = (0.2126 * rl + 0.7152 * gl + 0.0722 * bl);
    final z = (0.0193 * rl + 0.1192 * gl + 0.9505 * bl) / 1.08883;
    final fx = _labF(x), fy = _labF(y), fz = _labF(z);
    out[offset] = 116 * fy - 16;
    out[offset + 1] = 500 * (fx - fy);
    out[offset + 2] = 200 * (fy - fz);
  }

  /// Convierte todo un raster a un plano Lab (3 doubles por píxel).
  static Float64List rasterToLab(RgbRaster r) {
    final out = Float64List(r.width * r.height * 3);
    for (var i = 0, k = 0; i < r.width * r.height; i++, k += 3) {
      rgbToLab(r.data[k], r.data[k + 1], r.data[k + 2], out, k);
    }
    return out;
  }

  /// RGB (0–255) → HSV con H en grados [0,360), S y V en [0,1]. Escribe en [out].
  static void rgbToHsv(int r, int g, int b, Float64List out, [int offset = 0]) {
    final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
    final mx = math.max(rf, math.max(gf, bf));
    final mn = math.min(rf, math.min(gf, bf));
    final d = mx - mn;
    var h = 0.0;
    if (d > 1e-9) {
      if (mx == rf) {
        h = ((gf - bf) / d) % 6;
      } else if (mx == gf) {
        h = (bf - rf) / d + 2;
      } else {
        h = (rf - gf) / d + 4;
      }
      h *= 60;
      if (h < 0) h += 360;
    }
    out[offset] = h;
    out[offset + 1] = mx > 0 ? d / mx : 0.0;
    out[offset + 2] = mx;
  }

  static double labDistance(Float64List a, int ia, Float64List b, int ib) {
    final dl = a[ia] - b[ib], da = a[ia + 1] - b[ib + 1], db = a[ia + 2] - b[ib + 2];
    return math.sqrt(dl * dl + da * da + db * db);
  }

  /// ¿Está h (grados) dentro del arco [hMin, hMax]? Si hMin > hMax el arco
  /// cruza los 0/360 (p. ej. rojos: 335 → 25).
  static bool hueInRange(double h, double hMin, double hMax) =>
      hMin <= hMax ? (h >= hMin && h <= hMax) : (h >= hMin || h <= hMax);
}
