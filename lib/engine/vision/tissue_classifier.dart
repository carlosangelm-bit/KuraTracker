import 'dart:typed_data';

import 'color_spaces.dart';
import 'rasters.dart';
import 'vision_params.dart';
import 'wound_vision_models.dart';

/// Índices de clase del mapa de tejido (mismo orden que los sliders del lecho).
class TissueClass {
  const TissueClass._();
  static const int granulacion = 0;
  static const int esfacelo = 1;
  static const int necrosis = 2;
  static const int epitelizacion = 3;
  static const int none = 255;

  static const names = ['granulacion', 'esfacelo', 'necrosis', 'epitelizacion'];

  static int indexOf(String name) {
    final i = names.indexOf(name);
    return i < 0 ? none : i;
  }
}

/// Salida del clasificador: mapa de etiquetas (escala de trabajo) + porcentajes.
class TissueResult {
  final Uint8List labels; // por píxel de la máscara de trabajo; 255 fuera de la herida
  final TissueComposition composition;
  const TissueResult(this.labels, this.composition);
}

/// Contrato: sustituible por un modelo aprendido cuando exista dataset propio.
abstract class TissueClassifier {
  TissueResult classify(RgbRaster work, BitMask mask);
}

/// Clasificador por reglas HSV calibrables (vision_params.json → tissue.rules)
/// con respaldo al prototipo Lab más cercano. Los porcentajes se redondean a
/// enteros que suman exactamente 100 (los sliders del lecho exigen suma = 100).
class RuleTissueClassifier implements TissueClassifier {
  final VisionParams p;
  const RuleTissueClassifier(this.p);

  @override
  TissueResult classify(RgbRaster work, BitMask mask) {
    final n = work.width * work.height;
    final labels = Uint8List(n)..fillRange(0, n, TissueClass.none);
    final hsv = Float64List(3);
    final lab = Float64List(3);
    final protos = <int, Float64List>{
      for (final e in p.tissuePrototypesLab.entries)
        if (TissueClass.indexOf(e.key) != TissueClass.none) TissueClass.indexOf(e.key): Float64List.fromList(e.value),
    };
    final counts = List<int>.filled(4, 0);
    var total = 0;
    for (var i = 0, k = 0; i < n; i++, k += 3) {
      if (mask.data[i] == 0) continue;
      total++;
      final r = work.data[k], g = work.data[k + 1], b = work.data[k + 2];
      ColorSpaces.rgbToHsv(r, g, b, hsv);
      var cls = TissueClass.none;
      for (final rule in p.tissueRules) {
        if (_matches(rule, hsv[0], hsv[1], hsv[2])) {
          cls = TissueClass.indexOf(rule.tissueClass);
          break;
        }
      }
      if (cls == TissueClass.none) {
        ColorSpaces.rgbToLab(r, g, b, lab);
        var best = double.infinity;
        for (final e in protos.entries) {
          final d = ColorSpaces.labDistance(lab, 0, e.value, 0);
          if (d < best) {
            best = d;
            cls = e.key;
          }
        }
        if (cls == TissueClass.none) cls = TissueClass.granulacion;
      }
      labels[i] = cls;
      counts[cls]++;
    }
    if (total == 0) return TissueResult(labels, TissueComposition.zero);
    final pct = _roundTo100([for (final c in counts) c * 100.0 / total]);
    return TissueResult(
      labels,
      TissueComposition(
        granulacion: pct[TissueClass.granulacion],
        esfacelo: pct[TissueClass.esfacelo],
        necrosis: pct[TissueClass.necrosis],
        epitelizacion: pct[TissueClass.epitelizacion],
      ),
    );
  }

  static bool _matches(TissueRule r, double h, double s, double v) {
    if (r.vMax != null && v > r.vMax!) return false;
    if (r.vMin != null && v < r.vMin!) return false;
    if (r.sMax != null && s > r.sMax!) return false;
    if (r.sMin != null && s < r.sMin!) return false;
    if (r.hMin != null && r.hMax != null && !ColorSpaces.hueInRange(h, r.hMin!, r.hMax!)) return false;
    return true;
  }

  /// Redondeo por mayor residuo: enteros que suman exactamente 100.
  static List<double> _roundTo100(List<double> pct) {
    final floors = [for (final v in pct) v.floor()];
    var remaining = 100 - floors.reduce((a, b) => a + b);
    final order = List<int>.generate(pct.length, (i) => i)
      ..sort((a, b) => (pct[b] - floors[b]).compareTo(pct[a] - floors[a]));
    for (var i = 0; i < order.length && remaining > 0; i++, remaining--) {
      floors[order[i]]++;
    }
    return [for (final v in floors) v.toDouble()];
  }
}
