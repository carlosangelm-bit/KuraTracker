import 'dart:math' as math;
import 'dart:typed_data';

import 'rasters.dart';
import 'vision_geometry.dart';

/// Resultado de la corrección de iluminación.
class IlluminationCorrection {
  /// Nivel de negro estimado por canal (R,G,B), 0–255.
  final List<double> black;

  /// Nivel de blanco estimado por canal (R,G,B), 0–255.
  final List<double> white;

  /// Ganancia aplicada a cada canal (target / (white − black)).
  final List<double> gain;

  /// Desbalance cromático de la luz ANTES de corregir: max(gain)/min(gain).
  /// 1,0 = luz neutra. > ~1,3 = cast fuerte (tungsteno, fluorescente).
  final double castRatio;

  /// true si algún canal del blanco de referencia estaba saturado (≥ 254):
  /// la tarjeta quedó quemada y el cast ya no se puede recuperar del todo.
  final bool clipped;

  /// Rango dinámico mínimo entre canales (white − black).
  final double dynamicRange;

  const IlluminationCorrection({
    required this.black,
    required this.white,
    required this.gain,
    required this.castRatio,
    required this.clipped,
    required this.dynamicRange,
  });

  Map<String, dynamic> toJson() => {
        'black': [for (final v in black) double.parse(v.toStringAsFixed(1))],
        'white': [for (final v in white) double.parse(v.toStringAsFixed(1))],
        'gain': [for (final v in gain) double.parse(v.toStringAsFixed(3))],
        'cast_ratio': double.parse(castRatio.toStringAsFixed(3)),
        'dynamic_range': double.parse(dynamicRange.toStringAsFixed(1)),
        'clipped': clipped,
      };
}

/// Normaliza el color y la exposición de la foto usando la propia tarjeta de
/// calibración como referencia neutra.
///
/// **Por qué existe.** El clasificador de tejido trabaja con umbrales de tono y
/// brillo ABSOLUTOS (rojo = granulación, amarillo = esfacelo, oscuro =
/// necrosis). El color que registra la cámara depende de la luz de la sala y del
/// balance de blancos automático del teléfono: bajo lámpara cálida todo se corre
/// al rojo y el esfacelo amarillo deja de parecer amarillo. Medido sobre escenas
/// sintéticas, sin corregir: con luz de tungsteno el esfacelo pasa de 30 % a 0 %
/// y el área cae ~30 % (la segmentación deja de reconocer parte del lecho).
/// Con esta corrección los seis escenarios de luz quedan dentro de ±0,5 % de
/// área y ±1 punto de tejido.
///
/// Para el seguimiento serial —que es de lo que vive KuraTracker— esto importa
/// más que la exactitud de una sola foto: sin normalizar, un cambio de sala
/// entre dos visitas mueve los porcentajes del lecho y contamina la tendencia.
///
/// **Cómo.** La tarjeta trae dos referencias neutras gratis: el papel blanco y
/// la tinta negra de los marcadores. Se estiman por percentiles dentro de la
/// región de la tarjeta y se aplica una corrección diagonal (von Kries) por
/// canal: `out = (in − negro) / (blanco − negro) × objetivo`. Eso normaliza a la
/// vez el cast de color y la exposición.
///
/// **Límites.** Es una corrección DIAGONAL: arregla el cast global y la
/// exposición, no la respuesta espectral de la cámara (para eso harían falta
/// parches cromáticos con valores Lab medidos con espectrofotómetro, algo que
/// una impresión de oficina no garantiza). Tampoco corrige iluminación NO
/// uniforme: si la tarjeta está a la sombra y la herida al sol, una ganancia
/// global no basta. Y **no aplica en modo disco**, que no tiene referencia
/// neutra: ahí los porcentajes de tejido quedan a merced de la luz.
class IlluminationCorrector {
  const IlluminationCorrector._();

  /// Estima las referencias dentro de [cardRect] y devuelve la corrección, o
  /// null si la región no da un rango dinámico utilizable (tarjeta muy pequeña
  /// en el encuadre, plana de contraste, o fuera del área con datos).
  static IlluminationCorrection? estimate(
    RgbRaster rect,
    RectD cardRect, {
    required BitMask valid,
    required double whitePercentile,
    required double blackPercentile,
    required double targetWhite,
    required double minDynamicRange,
  }) {
    final x0 = cardRect.x0.floor().clamp(0, rect.width);
    final y0 = cardRect.y0.floor().clamp(0, rect.height);
    final x1 = cardRect.x1.ceil().clamp(0, rect.width);
    final y1 = cardRect.y1.ceil().clamp(0, rect.height);
    if (x1 - x0 < 8 || y1 - y0 < 8) return null;

    // Histograma por canal sobre los píxeles de la tarjeta CON dato.
    final hist = [Int32List(256), Int32List(256), Int32List(256)];
    var n = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        if (valid.data[y * valid.width + x] == 0) continue;
        final k = (y * rect.width + x) * 3;
        hist[0][rect.data[k]]++;
        hist[1][rect.data[k + 1]]++;
        hist[2][rect.data[k + 2]]++;
        n++;
      }
    }
    if (n < 100) return null;

    double percentile(Int32List h, double p) {
      final target = (p / 100 * n).clamp(1, n);
      var acc = 0;
      for (var v = 0; v < 256; v++) {
        acc += h[v];
        if (acc >= target) return v.toDouble();
      }
      return 255;
    }

    final black = <double>[], white = <double>[], gain = <double>[];
    var minRange = double.infinity;
    var clipped = false;
    for (var c = 0; c < 3; c++) {
      final b = percentile(hist[c], blackPercentile);
      final w = percentile(hist[c], whitePercentile);
      final range = w - b;
      black.add(b);
      white.add(w);
      gain.add(targetWhite / math.max(range, 1.0));
      minRange = math.min(minRange, range);
      if (w >= 254) clipped = true;
    }
    if (minRange < minDynamicRange) return null;
    final gMin = gain.reduce(math.min), gMax = gain.reduce(math.max);
    return IlluminationCorrection(
      black: black,
      white: white,
      gain: gain,
      castRatio: gMin <= 0 ? 1.0 : gMax / gMin,
      clipped: clipped,
      dynamicRange: minRange,
    );
  }

  /// Aplica [c] a todo el raster (devuelve uno nuevo). Se corrige la imagen
  /// COMPLETA, no solo la herida: la segmentación compara lecho contra piel
  /// perilesional y ambos deben quedar en el mismo espacio de color.
  static RgbRaster apply(RgbRaster rect, IlluminationCorrection c) {
    final out = RgbRaster(rect.width, rect.height);
    // Tabla de conversión por canal: 256 entradas, en vez de 3 multiplicaciones
    // por píxel (una foto rectificada puede tener > 1 M de píxeles).
    final lut = [Uint8List(256), Uint8List(256), Uint8List(256)];
    for (var ch = 0; ch < 3; ch++) {
      for (var v = 0; v < 256; v++) {
        final corrected = (v - c.black[ch]) * c.gain[ch];
        lut[ch][v] = corrected.round().clamp(0, 255);
      }
    }
    for (var i = 0; i < rect.data.length; i += 3) {
      out.data[i] = lut[0][rect.data[i]];
      out.data[i + 1] = lut[1][rect.data[i + 1]];
      out.data[i + 2] = lut[2][rect.data[i + 2]];
    }
    return out;
  }
}
