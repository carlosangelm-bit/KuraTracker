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

/// Banda de interpretación por rango de puntaje (modo `bands`).
///
/// CONVENCIÓN DE IDS (llaves estables): `id` es un CÓDIGO, no texto de UI. Se
/// usa como `band_id` en scale_assessments y como llave de las reglas de
/// acciones preventivas por escala (prevention_rules.json). Regla: snake_case
/// ASCII, sin acentos ni espacios, prefijado por la escala, p. ej.
/// `asepsis_infeccion_moderada`. NUNCA se traduce ni se acentúa: si cambia la
/// redacción clínica (`label`), el `id` NO cambia. El texto visible va en
/// `label`.
class ScaleBand {
  final String id;
  final int min;
  final int max;
  final String label; // texto visible (español)
  final String? severity; // ok | watch | warn | danger
  const ScaleBand({
    required this.id,
    required this.min,
    required this.max,
    required this.label,
    this.severity,
  });
  factory ScaleBand.fromJson(Map<String, dynamic> j) => ScaleBand(
        id: j['id'] as String,
        min: (j['min'] as num).toInt(),
        max: (j['max'] as num).toInt(),
        label: j['label'] as String,
        severity: j['severity'] as String?,
      );
}

/// Lectura de un puntaje: `bandId` = CÓDIGO ESTABLE (band_id, llave de reglas);
/// `label` = texto visible; `severity` = ok|watch|warn|danger; `delta` = cambio
/// vs la valoración previa (solo modo `trend`).
typedef ScaleReading = ({
  String? bandId,
  String? label,
  String? severity,
  num? delta,
});

/// Interpretación de una escala de suma, en dos modos:
///  - `bands`: lectura por rango (min..max) → banda con id estable + etiqueta.
///    Sirve a escalas con lectura por corte (ASEPSIS: 5 bandas).
///  - `trend`: índice de SEGUIMIENTO (PUSH/RESVECH); la lectura sale de comparar
///    con la valoración previa según `direction`/`minDelta`. Sin previa (primera
///    valoración) → sin lectura (solo puntaje).
/// Compatibilidad: el shape viejo (`threshold`/`above`/`below`) se traduce a dos
/// bandas para que un asset sin migrar no rompa.
class ScaleInterpretation {
  final String mode; // 'bands' | 'trend'
  final bool draft;
  final List<ScaleBand> bands; // modo bands (en línea)
  final String? bandsRef; // modo bands por referencia a ClinicalParams.scaleBands
  final String direction; // trend: lower_is_better | higher_is_better
  final num minDelta; // trend: |delta| < minDelta ⇒ sin cambio
  final String improvingLabel;
  final String stableLabel;
  final String worseningLabel;
  const ScaleInterpretation({
    required this.mode,
    this.draft = false,
    this.bands = const [],
    this.bandsRef,
    this.direction = 'lower_is_better',
    this.minDelta = 1,
    this.improvingLabel = 'Mejorando',
    this.stableLabel = 'Sin cambio',
    this.worseningLabel = 'Empeorando',
  });

  static ScaleInterpretation? fromJson(
    Map<String, dynamic>? j, {
    required String scaleId,
    required int totalMin,
    required int totalMax,
  }) {
    if (j == null) return null;
    final draft = j['draft'] as bool? ?? false;
    final mode = j['mode'] as String?;
    if (mode == 'trend') {
      final labels = (j['labels'] as Map?)?.cast<String, dynamic>() ?? const {};
      return ScaleInterpretation(
        mode: 'trend',
        draft: draft,
        direction: (j['direction'] as String?) ?? 'lower_is_better',
        minDelta: (j['min_delta'] as num?) ?? 1,
        improvingLabel: labels['improving'] as String? ?? 'Mejorando',
        stableLabel: labels['stable'] as String? ?? 'Sin cambio',
        worseningLabel: labels['worsening'] as String? ?? 'Empeorando',
      );
    }
    // Bandas por referencia (FUENTE ÚNICA en ClinicalParams.scaleBands).
    if (j['bands_ref'] != null) {
      return ScaleInterpretation(
          mode: 'bands', draft: draft, bandsRef: j['bands_ref'] as String);
    }
    if (mode == 'bands' || j['bands'] != null) {
      final bands = ((j['bands'] as List?) ?? const [])
          .map((e) => ScaleBand.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      return ScaleInterpretation(mode: 'bands', draft: draft, bands: bands);
    }
    // Compat: shape viejo threshold/above/below → dos bandas con ids estables.
    if (j['threshold'] != null) {
      final t = (j['threshold'] as num).toInt();
      final above = j['above'] as String?;
      final below = j['below'] as String?;
      final sid = scaleId.toLowerCase();
      return ScaleInterpretation(mode: 'bands', draft: draft, bands: [
        if (below != null)
          ScaleBand(
              id: '${sid}_below',
              min: totalMin,
              max: t,
              label: below,
              severity: 'ok'),
        if (above != null)
          ScaleBand(
              id: '${sid}_above',
              min: t + 1,
              max: totalMax,
              label: above,
              severity: 'warn'),
      ]);
    }
    return null;
  }

  ScaleReading read(num total, {num? previousTotal}) {
    if (mode == 'trend') {
      if (previousTotal == null) {
        return (bandId: null, label: null, severity: null, delta: null);
      }
      final delta = total - previousTotal;
      final stable = delta.abs() < minDelta;
      final lowerBetter = direction == 'lower_is_better';
      final improving = !stable && (lowerBetter ? delta < 0 : delta > 0);
      final label =
          stable ? stableLabel : (improving ? improvingLabel : worseningLabel);
      final sev = stable ? 'watch' : (improving ? 'ok' : 'danger');
      return (bandId: null, label: label, severity: sev, delta: delta);
    }
    // Bandas por referencia: FUENTE ÚNICA en ClinicalParams (bordes abiertos/
    // cerrados → un total double cae siempre en una banda). Fallback a las
    // bandas en línea si el parámetro no está cargado o no existe la referencia.
    if (bandsRef != null && ClinicalParams.isLoaded) {
      final pbands = ClinicalParams.instance.scaleBandsFor(bandsRef!);
      if (pbands != null && pbands.isNotEmpty) {
        for (final b in pbands) {
          if (b.contains(total)) {
            return (
              bandId: b.band,
              label: b.label,
              severity: b.severity,
              delta: null
            );
          }
        }
        return (bandId: null, label: null, severity: null, delta: null);
      }
    }
    for (final b in bands) {
      if (total >= b.min && total <= b.max) {
        return (bandId: b.id, label: b.label, severity: b.severity, delta: null);
      }
    }
    return (bandId: null, label: null, severity: null, delta: null);
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
  /// Interpretación clínica del puntaje (bandas o tendencia). null = la escala
  /// aún no define interpretación → se muestra solo el puntaje.
  final ScaleInterpretation? interpretation;
  const SumScaleDef({
    required this.scaleId,
    required this.title,
    required this.totalMin,
    required this.totalMax,
    required this.draft,
    required this.items,
    this.interpretation,
  });

  factory SumScaleDef.fromJson(Map<String, dynamic> j) {
    final scaleId = j['scale_id'] as String;
    final totalMin = (j['total_min'] as num?)?.toInt() ?? 0;
    final totalMax = (j['total_max'] as num?)?.toInt() ?? 0;
    return SumScaleDef(
      scaleId: scaleId,
      title: (j['title'] as String?) ?? scaleId,
      totalMin: totalMin,
      totalMax: totalMax,
      draft: j['draft'] as bool? ?? false,
      items: ((j['items'] as List?) ?? const [])
          .map((e) => SumItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      interpretation: ScaleInterpretation.fromJson(
        (j['interpretation'] as Map?)?.cast<String, dynamic>(),
        scaleId: scaleId,
        totalMin: totalMin,
        totalMax: totalMax,
      ),
    );
  }

  /// Interpreta un [total] (opcionalmente contra la valoración [previousTotal],
  /// para el modo tendencia). Sin interpretación declarada → todo null.
  ScaleReading interpret(num total, {num? previousTotal}) =>
      interpretation?.read(total, previousTotal: previousTotal) ??
      (bandId: null, label: null, severity: null, delta: null);

  static final Map<String, SumScaleDef> _cache = {};

  /// Carga la definición de una escala SUMA por su id
  /// (assets/engine/scales/<id>.json). Se cachea sin cambios.
  static Future<SumScaleDef> load(String scaleId) async {
    var def = _cache[scaleId];
    if (def == null) {
      final raw = await rootBundle
          .loadString('assets/engine/scales/${scaleId.toLowerCase()}.json');
      def = SumScaleDef.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _cache[scaleId] = def;
    }
    return def;
  }
}
