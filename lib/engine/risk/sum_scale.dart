import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../params/clinical_params.dart';

/// Rango de área (cm²) → puntos, para ítems de tipo 'area' (PUSH). Se evalúa el
/// primer rango cuyo `maxLtE` cubre el área; si ninguno, `overflowPoints`.
class AreaRange {
  final double maxLtE;
  final int points;
  const AreaRange(this.maxLtE, this.points);
  factory AreaRange.fromJson(Map<String, dynamic> j) =>
      AreaRange((j['maxLtE'] as num).toDouble(), (j['points'] as num).toInt());
}

/// Opción puntuada de un ítem radio.
class SumOption {
  final int score;
  final String label;
  const SumOption(this.score, this.label);
  factory SumOption.fromJson(Map<String, dynamic> j) =>
      SumOption((j['score'] as num).toInt(), j['label'] as String);
}

/// Ítem de una escala SUMA: radio (opciones puntuadas) o area (medición → puntos).
class SumItem {
  final String id;
  final String label;
  final String type; // 'radio' | 'area'
  final List<SumOption> options; // radio
  final List<AreaRange> ranges; // area
  final int overflowPoints; // area: puntos si excede el último rango
  const SumItem({
    required this.id,
    required this.label,
    required this.type,
    this.options = const [],
    this.ranges = const [],
    this.overflowPoints = 0,
  });

  factory SumItem.fromJson(Map<String, dynamic> j) => SumItem(
        id: j['id'] as String,
        label: j['label'] as String,
        type: (j['type'] as String?) ?? 'radio',
        options: ((j['options'] as List?) ?? const [])
            .map((e) => SumOption.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        ranges: ((j['ranges'] as List?) ?? const [])
            .map((e) => AreaRange.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        overflowPoints: (j['overflow_points'] as num?)?.toInt() ?? 0,
      );

  /// Puntos para un área (cm²) según los rangos (ítem tipo 'area').
  int pointsForArea(double areaCm2) {
    for (final r in ranges) {
      if (areaCm2 <= r.maxLtE) return r.points;
    }
    return overflowPoints;
  }
}

/// Definición declarativa de una escala tipo SUMA (PUSH, RESVECH, ASEPSIS…).
/// Se carga de un asset; los sub-puntajes son parametrizables (editables sin
/// recompilar) y, en escalas marcadas `draft`, PENDIENTES de validación clínica.
class SumScaleDef {
  final String scaleId;
  final String title;
  final int totalMin;
  final int totalMax;
  final bool draft;
  final List<SumItem> items;
  // Interpretación por umbral: si total > threshold → aboveLabel (p. ej. ASEPSIS
  // > 20 = "Infección de sitio quirúrgico"); si total ≤ threshold → belowLabel
  // (opcional, lo llena María). null = sin interpretación.
  final int? threshold;
  final String? aboveLabel;
  final String? belowLabel;
  const SumScaleDef({
    required this.scaleId,
    required this.title,
    required this.totalMin,
    required this.totalMax,
    required this.draft,
    required this.items,
    this.threshold,
    this.aboveLabel,
    this.belowLabel,
  });

  factory SumScaleDef.fromJson(Map<String, dynamic> j) {
    final interp = (j['interpretation'] as Map?)?.cast<String, dynamic>();
    return SumScaleDef(
      scaleId: j['scale_id'] as String,
      title: (j['title'] as String?) ?? j['scale_id'] as String,
      totalMin: (j['total_min'] as num?)?.toInt() ?? 0,
      totalMax: (j['total_max'] as num?)?.toInt() ?? 0,
      draft: j['draft'] as bool? ?? false,
      items: ((j['items'] as List?) ?? const [])
          .map((e) => SumItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      threshold: (interp?['threshold'] as num?)?.toInt(),
      aboveLabel: interp?['above'] as String?,
      belowLabel: interp?['below'] as String?,
    );
  }

  /// Banda/categoría clínica para un [total], resuelta desde la interpretación
  /// declarada en el asset. null si la escala aún no define interpretación
  /// (p. ej. PUSH/RESVECH, pendientes de contenido de María) → se muestra solo
  /// el puntaje.
  String? bandFor(num total) {
    if (threshold == null) return null;
    return total > threshold! ? aboveLabel : belowLabel;
  }

  /// Devuelve una copia con el [threshold] de interpretación sustituido.
  SumScaleDef _withThreshold(int t) => SumScaleDef(
        scaleId: scaleId,
        title: title,
        totalMin: totalMin,
        totalMax: totalMax,
        draft: draft,
        items: items,
        threshold: t,
        aboveLabel: aboveLabel,
        belowLabel: belowLabel,
      );

  static final Map<String, SumScaleDef> _cache = {};

  /// Escalas cuyo umbral de interpretación es parametrizable vía ClinicalParams
  /// (revisable por María). scale_id → clave de umbral en thresholds.json.
  static const Map<String, String> _thresholdParamKey = {
    'ASEPSIS': 'asepsis_isq_above',
  };

  /// Carga la definición de una escala SUMA por su id (assets/engine/scales/<id>.json).
  /// El asset se cachea sin cambios; el umbral parametrizable se resuelve desde
  /// ClinicalParams en CADA llamada (así un cambio del master surte efecto sin
  /// invalidar la caché del asset).
  static Future<SumScaleDef> load(String scaleId) async {
    var def = _cache[scaleId];
    if (def == null) {
      final raw = await rootBundle
          .loadString('assets/engine/scales/${scaleId.toLowerCase()}.json');
      def = SumScaleDef.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _cache[scaleId] = def;
    }
    final paramKey = _thresholdParamKey[scaleId.toUpperCase()];
    if (paramKey != null && ClinicalParams.isLoaded) {
      final v = ClinicalParams.instance.thresholds[paramKey];
      if (v != null && v.toInt() != def.threshold) {
        def = def._withThreshold(v.toInt());
      }
    }
    return def;
  }
}
