import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import 'models/kura_engine_enums.dart';
import 'models/kura_engine_input.dart';

/// Ajustes clinicos por perfusion (ABI/ITB) y nutricion (albumina) —
/// seccion 8.2 de la especificacion. Se suman en log-odds a los scores
/// crudos del modelo pronostico ANTES de aplicar softmax.
///
/// Estos pesos vienen de guia clinica, NO estan calibrados con datos, y
/// deben revalidarse prospectivamente (aviso obligatorio en UI, seccion 11).
class KuraClinicalAdjustments {
  final String adjustmentsVersion;
  final Map<String, Map<String, double>> itb; // categoria -> {A,B,C}
  final Map<String, Map<String, double>> alb; // categoria -> {A,B,C}
  final double itbHighMin;
  final double itbModMin;
  final double albNormalMin;
  final double albMildMin;

  const KuraClinicalAdjustments({
    required this.adjustmentsVersion,
    required this.itb,
    required this.alb,
    required this.itbHighMin,
    required this.itbModMin,
    required this.albNormalMin,
    required this.albMildMin,
  });

  static KuraClinicalAdjustments? _cached;

  static Future<KuraClinicalAdjustments> loadFromAssets({
    String assetPath = 'assets/engine/kura_clinical_adjustments.json',
  }) async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString(assetPath);
    final adj = KuraClinicalAdjustments.fromJsonString(raw);
    _cached = adj;
    return adj;
  }

  factory KuraClinicalAdjustments.fromJsonString(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return KuraClinicalAdjustments.fromJson(json);
  }

  factory KuraClinicalAdjustments.fromJson(Map<String, dynamic> json) {
    Map<String, Map<String, double>> _catMap(Map<String, dynamic> m) => m.map(
          (cat, scores) => MapEntry(
            cat,
            (scores as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, (v as num).toDouble()),
            ),
          ),
        );
    final thresholdsItb = json['itb_thresholds'] as Map<String, dynamic>;
    final thresholdsAlb = json['alb_thresholds'] as Map<String, dynamic>;
    return KuraClinicalAdjustments(
      adjustmentsVersion: json['adjustments_version'] as String,
      itb: _catMap(json['itb'] as Map<String, dynamic>),
      alb: _catMap(json['alb'] as Map<String, dynamic>),
      itbHighMin: (thresholdsItb['high_min'] as num).toDouble(),
      itbModMin: (thresholdsItb['mod_min'] as num).toDouble(),
      albNormalMin: (thresholdsAlb['normal_min'] as num).toDouble(),
      albMildMin: (thresholdsAlb['mild_min'] as num).toDouble(),
    );
  }

  String _abiCategoryKey(AbiCategory c) {
    switch (c) {
      case AbiCategory.na:
        return 'na';
      case AbiCategory.high:
        return 'high';
      case AbiCategory.mod:
        return 'mod';
      case AbiCategory.low:
        return 'low';
    }
  }

  String _albCategoryKey(AlbCategory c) {
    switch (c) {
      case AlbCategory.na:
        return 'na';
      case AlbCategory.normal:
        return 'normal';
      case AlbCategory.mild:
        return 'mild';
      case AlbCategory.low:
        return 'low';
    }
  }

  /// Aplica los ajustes de ABI y albumina a los scores crudos del modelo,
  /// devolviendo nuevos scores ajustados (aun sin softmax).
  Map<String, double> applyAdjustments({
    required Map<String, double> rawScores,
    required KuraEngineInput input,
  }) {
    final abiKey = _abiCategoryKey(input.abiCategory);
    final albKey = _albCategoryKey(input.albCategory);

    final itbAdj = itb[abiKey] ?? const {'A': 0.0, 'B': 0.0, 'C': 0.0};
    final albAdj = alb[albKey] ?? const {'A': 0.0, 'B': 0.0, 'C': 0.0};

    final adjusted = <String, double>{};
    for (final cls in ['A', 'B', 'C']) {
      adjusted[cls] =
          (rawScores[cls] ?? 0.0) + (itbAdj[cls] ?? 0.0) + (albAdj[cls] ?? 0.0);
    }
    return adjusted;
  }
}
