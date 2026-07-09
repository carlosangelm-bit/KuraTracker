import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;

import 'models/kura_engine_enums.dart';
import 'models/kura_engine_input.dart';

/// Modelo pronostico multinomial (3 clases A/B/C) — seccion 8.1 de la
/// especificacion. Carga los coeficientes desde `assets/engine/kura_model_v2.json`
/// para poder actualizar el modelo sin recompilar la logica.
///
/// IMPORTANTE: esta clase reproduce EXACTAMENTE la aritmetica especificada:
///   z = (x - mean) / scale
///   s_clase = intercept_clase + sum(coef_clase[i] * z[i])
///   p = softmax(s_A, s_B, s_C)
class KuraPrognosisModel {
  final String modelVersion;
  final List<String> featureOrder;
  final Map<String, double> intercept;
  final Map<String, Map<String, double>> coef;
  final Map<String, double> mean;
  final Map<String, double> scale;

  const KuraPrognosisModel({
    required this.modelVersion,
    required this.featureOrder,
    required this.intercept,
    required this.coef,
    required this.mean,
    required this.scale,
  });

  static KuraPrognosisModel? _cached;

  /// Carga el modelo desde el asset empaquetado. Se cachea en memoria tras
  /// la primera carga.
  static Future<KuraPrognosisModel> loadFromAssets({
    String assetPath = 'assets/engine/kura_model_v2.json',
  }) async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString(assetPath);
    final model = KuraPrognosisModel.fromJsonString(raw);
    _cached = model;
    return model;
  }

  factory KuraPrognosisModel.fromJsonString(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return KuraPrognosisModel.fromJson(json);
  }

  factory KuraPrognosisModel.fromJson(Map<String, dynamic> json) {
    Map<String, double> _numMap(Map<String, dynamic> m) =>
        m.map((k, v) => MapEntry(k, (v as num).toDouble()));

    final coefRaw = (json['coef'] as Map<String, dynamic>);
    final coef = coefRaw.map(
      (cls, m) => MapEntry(cls, _numMap(m as Map<String, dynamic>)),
    );

    return KuraPrognosisModel(
      modelVersion: json['model_version'] as String,
      featureOrder: (json['feature_order'] as List).cast<String>(),
      intercept: _numMap(json['intercept'] as Map<String, dynamic>),
      coef: coef,
      mean: _numMap(json['mean'] as Map<String, dynamic>),
      scale: _numMap(json['scale'] as Map<String, dynamic>),
    );
  }

  /// Calcula el vector de features en el orden especificado (8.1):
  /// logarea, necrosis_f, esfacelo_f, depth_f, n_comorb_struct,
  /// et_lpp, et_vasc, et_quir, et_traum
  Map<String, double> computeFeatures(KuraEngineInput input) {
    final logarea = math.log(1 + input.areaCm2);
    final etLpp = input.etiologia == Etiologia.lpp ? 1.0 : 0.0;
    final etVasc = input.etiologia == Etiologia.vascular ? 1.0 : 0.0;
    final etQuir = input.etiologia == Etiologia.quirurgica ? 1.0 : 0.0;
    final etTraum = input.etiologia == Etiologia.traumatica ? 1.0 : 0.0;
    // pieDiabetico y otra quedan implicitamente en 0,0,0,0 (categoria base)

    return {
      'logarea': logarea,
      'necrosis_f': input.necrosisPct,
      'esfacelo_f': input.esfaceloPct,
      'depth_f': input.depthCm,
      'n_comorb_struct': input.nComorbStruct.toDouble(),
      'et_lpp': etLpp,
      'et_vasc': etVasc,
      'et_quir': etQuir,
      'et_traum': etTraum,
    };
  }

  /// Estandariza los features: z = (x - mean) / scale
  Map<String, double> standardize(Map<String, double> features) {
    final z = <String, double>{};
    for (final key in featureOrder) {
      final x = features[key] ?? 0.0;
      final m = mean[key] ?? 0.0;
      final s = scale[key] ?? 1.0;
      z[key] = s == 0 ? 0.0 : (x - m) / s;
    }
    return z;
  }

  /// Calcula los scores lineales (log-odds sin normalizar) por clase:
  /// s_clase = intercept_clase + sum(coef_clase[i] * z[i])
  Map<String, double> computeRawScores(Map<String, double> z) {
    final scores = <String, double>{};
    for (final cls in ['A', 'B', 'C']) {
      double s = intercept[cls] ?? 0.0;
      final classCoef = coef[cls] ?? {};
      for (final key in featureOrder) {
        s += (classCoef[key] ?? 0.0) * (z[key] ?? 0.0);
      }
      scores[cls] = s;
    }
    return scores;
  }

  /// Softmax numerico estable sobre los 3 scores.
  static Map<String, double> softmax(Map<String, double> scores) {
    final keys = scores.keys.toList();
    final values = keys.map((k) => scores[k]!).toList();
    final maxVal = values.reduce(math.max);
    final exps = values.map((v) => math.exp(v - maxVal)).toList();
    final sumExp = exps.fold<double>(0.0, (a, b) => a + b);
    final result = <String, double>{};
    for (var i = 0; i < keys.length; i++) {
      result[keys[i]] = exps[i] / sumExp;
    }
    return result;
  }

  /// Pipeline completo sin ajustes clinicos: features -> z -> scores.
  /// Devuelve tambien los features y z para depuracion/trazabilidad.
  ({
    Map<String, double> features,
    Map<String, double> z,
    Map<String, double> rawScores,
  }) computePipeline(KuraEngineInput input) {
    final features = computeFeatures(input);
    final z = standardize(features);
    final rawScores = computeRawScores(z);
    return (features: features, z: z, rawScores: rawScores);
  }
}
