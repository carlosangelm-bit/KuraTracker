import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Una opción de respuesta de una subescala de Braden.
class BradenOption {
  final int score;
  final String label;
  const BradenOption({required this.score, required this.label});

  factory BradenOption.fromJson(Map<String, dynamic> j) =>
      BradenOption(score: (j['score'] as num).toInt(), label: j['label'] as String);
}

/// Una subescala (ítem) de Braden con sus opciones.
class BradenItem {
  final String id;
  final String label;
  final int minScore;
  final int maxScore;
  final List<BradenOption> options;

  const BradenItem({
    required this.id,
    required this.label,
    required this.minScore,
    required this.maxScore,
    required this.options,
  });

  factory BradenItem.fromJson(Map<String, dynamic> j) => BradenItem(
        id: j['id'] as String,
        label: j['label'] as String,
        minScore: (j['min_score'] as num?)?.toInt() ?? 1,
        maxScore: (j['max_score'] as num?)?.toInt() ?? 4,
        options: ((j['options'] as List?) ?? const [])
            .map((e) => BradenOption.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// Banda de riesgo por rango de puntaje total.
class BradenRiskBand {
  final String id;
  final String label;
  final int minScore;
  final int maxScore;
  const BradenRiskBand(
      {required this.id,
      required this.label,
      required this.minScore,
      required this.maxScore});

  factory BradenRiskBand.fromJson(Map<String, dynamic> j) => BradenRiskBand(
        id: j['id'] as String,
        label: j['label'] as String,
        minScore: (j['min_score'] as num).toInt(),
        maxScore: (j['max_score'] as num).toInt(),
      );
}

/// Definición de la escala de Braden (asset configurable). Permite llenar las
/// 6 subescalas en la app y calcular el total automáticamente.
/// Patrón de carga igual que los demás assets del motor.
class BradenScale {
  final int totalMin;
  final int totalMax;
  final List<BradenItem> items;
  final List<BradenRiskBand> riskLevels;

  const BradenScale({
    required this.totalMin,
    required this.totalMax,
    required this.items,
    required this.riskLevels,
  });

  static BradenScale? _cached;

  static Future<BradenScale> load({
    String assetPath = 'assets/engine/braden_scale.json',
  }) async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString(assetPath);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final scale = BradenScale(
      totalMin: (j['total_score_min'] as num?)?.toInt() ?? 6,
      totalMax: (j['total_score_max'] as num?)?.toInt() ?? 23,
      items: ((j['items'] as List?) ?? const [])
          .map((e) => BradenItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      riskLevels: ((j['risk_levels'] as List?) ?? const [])
          .map((e) => BradenRiskBand.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
    _cached = scale;
    return scale;
  }

  /// Etiqueta de la banda de riesgo para un puntaje total (o null).
  String? riskLabelFor(int total) {
    for (final b in riskLevels) {
      if (total >= b.minScore && total <= b.maxScore) return b.label;
    }
    return null;
  }
}
