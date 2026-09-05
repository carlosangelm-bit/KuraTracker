import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'apriltag_detector.dart';
import 'vision_geometry.dart';

/// Geometría física de la tarjeta WoundCalibrate (espejo de
/// tools/wound_calibrate_proto/card_spec.json). Coordenadas en mm, origen en la
/// esquina superior izquierda de la tarjeta, eje Y hacia ABAJO.
class CardSpec {
  final bool isPlaceholder;
  final double widthMm;
  final double heightMm;
  final List<CardTagSpec> tags;
  final double circleDiameterMm;
  final Pt circleCenterMm;
  final String circleCheckMode; // 'solid' | 'skip'

  const CardSpec({
    required this.isPlaceholder,
    required this.widthMm,
    required this.heightMm,
    required this.tags,
    required this.circleDiameterMm,
    required this.circleCenterMm,
    this.circleCheckMode = 'solid',
  });

  factory CardSpec.fromJson(Map<String, dynamic> j) {
    final size = j['card_size_mm'] as Map<String, dynamic>;
    final circle = j['reference_circle'] as Map<String, dynamic>;
    final cc = circle['center_mm'] as List;
    return CardSpec(
      isPlaceholder: j['is_placeholder'] as bool? ?? false,
      widthMm: (size['width'] as num).toDouble(),
      heightMm: (size['height'] as num).toDouble(),
      tags: [
        for (final t in (j['tags'] as List)) CardTagSpec.fromJson((t as Map).cast<String, dynamic>()),
      ],
      circleDiameterMm: (circle['diameter_mm'] as num).toDouble(),
      circleCenterMm: Pt((cc[0] as num).toDouble(), (cc[1] as num).toDouble()),
      circleCheckMode: circle['check_mode'] as String? ?? 'solid',
    );
  }

  List<int> get tagIds => [for (final t in tags) t.id];
}

class CardTagSpec {
  final int id;
  final Pt centerMm;
  final double sizeMm;
  const CardTagSpec({required this.id, required this.centerMm, required this.sizeMm});

  factory CardTagSpec.fromJson(Map<String, dynamic> j) {
    final c = j['center_mm'] as List;
    return CardTagSpec(
      id: (j['id'] as num).toInt(),
      centerMm: Pt((c[0] as num).toDouble(), (c[1] as num).toDouble()),
      sizeMm: (j['size_mm'] as num).toDouble(),
    );
  }
}

/// Regla de clasificación de tejido por píxel en HSV. Los campos ausentes no
/// restringen. `hMin > hMax` significa arco que cruza 0/360 (rojos).
class TissueRule {
  final String tissueClass; // granulacion | esfacelo | necrosis | epitelizacion
  final double? hMin, hMax, sMin, sMax, vMin, vMax;
  const TissueRule({
    required this.tissueClass,
    this.hMin,
    this.hMax,
    this.sMin,
    this.sMax,
    this.vMin,
    this.vMax,
  });

  factory TissueRule.fromJson(Map<String, dynamic> j) => TissueRule(
        tissueClass: j['class'] as String,
        hMin: (j['h_min'] as num?)?.toDouble(),
        hMax: (j['h_max'] as num?)?.toDouble(),
        sMin: (j['s_min'] as num?)?.toDouble(),
        sMax: (j['s_max'] as num?)?.toDouble(),
        vMin: (j['v_min'] as num?)?.toDouble(),
        vMax: (j['v_max'] as num?)?.toDouble(),
      );
}

/// Parámetros del motor de visión (assets/engine/vision/vision_params.json).
/// Todos los umbrales viven aquí, no en el código, para que puedan ajustarse
/// con fotos reales sin recompilar la lógica (misma filosofía que
/// ClinicalParams).
class VisionParams {
  final AprilTagDetectorParams tagDetector;

  // Rectificación
  final double targetPxPerMm;
  final int rectifyMaxSidePx;
  final double rectifyMaxMarginMm;

  // Compuertas de calidad
  final double planarityMaxSideErrorPct;
  final double circleDiameterTolPct;
  final double overexposedMaxFraction;
  final int overexposedThreshold;
  final double minTagSidePx; // proxy de distancia: tag demasiado pequeño → lejos
  final double discTiltMinRatio;

  // Segmentación
  final int workMaxSidePx;
  final int seedPatchRadiusPx;
  final int ringWidthPx;
  final int iterations;
  final int subClusters;
  final int closeRadiusPx;
  final int openRadiusPx;
  final double sensitivityDefault;
  final double sensitivitySpan;
  final double stageADeltaE;
  final double roiExpand;
  final int roiPadPx;
  final double roiBandFrac;
  final List<String> prototypeClasses;
  final double contourEpsilonPx;

  // Tejido
  final List<TissueRule> tissueRules;
  final Map<String, List<double>> tissuePrototypesLab;

  // Disco de respaldo
  final double discDiameterMm;
  final double discHueMin, discHueMax, discSMin, discVMin;
  final int discMinAreaPx;
  final double discFillMin, discAspectMin;

  const VisionParams({
    required this.tagDetector,
    required this.targetPxPerMm,
    required this.rectifyMaxSidePx,
    required this.rectifyMaxMarginMm,
    required this.planarityMaxSideErrorPct,
    required this.circleDiameterTolPct,
    required this.overexposedMaxFraction,
    required this.overexposedThreshold,
    required this.minTagSidePx,
    required this.discTiltMinRatio,
    required this.workMaxSidePx,
    required this.seedPatchRadiusPx,
    required this.ringWidthPx,
    required this.iterations,
    required this.subClusters,
    required this.closeRadiusPx,
    required this.openRadiusPx,
    required this.sensitivityDefault,
    required this.sensitivitySpan,
    required this.stageADeltaE,
    required this.roiExpand,
    required this.roiPadPx,
    required this.roiBandFrac,
    required this.prototypeClasses,
    required this.contourEpsilonPx,
    required this.tissueRules,
    required this.tissuePrototypesLab,
    required this.discDiameterMm,
    required this.discHueMin,
    required this.discHueMax,
    required this.discSMin,
    required this.discVMin,
    required this.discMinAreaPx,
    required this.discFillMin,
    required this.discAspectMin,
  });

  factory VisionParams.fromJson(Map<String, dynamic> j) {
    final rect = (j['rectify'] as Map).cast<String, dynamic>();
    final q = (j['quality'] as Map).cast<String, dynamic>();
    final s = (j['segmentation'] as Map).cast<String, dynamic>();
    final t = (j['tissue'] as Map).cast<String, dynamic>();
    final d = (j['fallback_disc'] as Map).cast<String, dynamic>();
    final protos = (t['prototypes_lab'] as Map).cast<String, dynamic>();
    return VisionParams(
      tagDetector: AprilTagDetectorParams.fromJson(
          ((j['tag_detector'] as Map?) ?? const {}).cast<String, dynamic>()),
      targetPxPerMm: (rect['target_px_per_mm'] as num).toDouble(),
      rectifyMaxSidePx: (rect['max_side_px'] as num).toInt(),
      rectifyMaxMarginMm: (rect['max_margin_mm'] as num).toDouble(),
      planarityMaxSideErrorPct: (q['planarity_max_side_error_pct'] as num).toDouble(),
      circleDiameterTolPct: (q['circle_diameter_tol_pct'] as num).toDouble(),
      overexposedMaxFraction: (q['overexposed_max_fraction'] as num).toDouble(),
      overexposedThreshold: (q['overexposed_threshold_255'] as num).toInt(),
      minTagSidePx: (q['min_tag_side_px'] as num).toDouble(),
      discTiltMinRatio: (q['disc_tilt_min_ratio'] as num).toDouble(),
      workMaxSidePx: (s['work_max_side_px'] as num).toInt(),
      seedPatchRadiusPx: (s['seed_patch_radius_px'] as num).toInt(),
      ringWidthPx: (s['ring_width_px'] as num).toInt(),
      iterations: (s['iterations'] as num).toInt(),
      subClusters: (s['sub_clusters'] as num).toInt(),
      closeRadiusPx: (s['close_radius_px'] as num).toInt(),
      openRadiusPx: (s['open_radius_px'] as num).toInt(),
      sensitivityDefault: (s['sensitivity_default'] as num).toDouble(),
      sensitivitySpan: (s['sensitivity_span'] as num).toDouble(),
      stageADeltaE: (s['stage_a_delta_e'] as num).toDouble(),
      roiExpand: (s['roi_expand'] as num).toDouble(),
      roiPadPx: (s['roi_pad_px'] as num).toInt(),
      roiBandFrac: (s['roi_band_frac'] as num).toDouble(),
      prototypeClasses: (s['prototype_classes'] as List).cast<String>(),
      contourEpsilonPx: (s['contour_epsilon_px'] as num).toDouble(),
      tissueRules: [
        for (final r in (t['rules'] as List)) TissueRule.fromJson((r as Map).cast<String, dynamic>()),
      ],
      tissuePrototypesLab: {
        for (final e in protos.entries) e.key: (e.value as List).map((v) => (v as num).toDouble()).toList(),
      },
      discDiameterMm: (d['diameter_mm'] as num).toDouble(),
      discHueMin: (d['hue_min'] as num).toDouble(),
      discHueMax: (d['hue_max'] as num).toDouble(),
      discSMin: (d['s_min'] as num).toDouble(),
      discVMin: (d['v_min'] as num).toDouble(),
      discMinAreaPx: (d['min_area_px'] as num).toInt(),
      discFillMin: (d['fill_min'] as num).toDouble(),
      discAspectMin: (d['aspect_min'] as num).toDouble(),
    );
  }

  static VisionParams fromJsonString(String s) =>
      VisionParams.fromJson((jsonDecode(s) as Map).cast<String, dynamic>());
}

/// Carga de los dos JSON del motor de visión desde los assets. Misma
/// disciplina que ClinicalParams: instancia global registrable (tests pueden
/// inyectar la suya leyendo los archivos con dart:io).
class VisionAssets {
  const VisionAssets._();

  static const cardSpecPath = 'assets/engine/vision/card_spec.json';
  static const paramsPath = 'assets/engine/vision/vision_params.json';

  static CardSpec? _cardSpec;
  static VisionParams? _params;

  static void register({CardSpec? cardSpec, VisionParams? params}) {
    if (cardSpec != null) _cardSpec = cardSpec;
    if (params != null) _params = params;
  }

  static void resetForTest() {
    _cardSpec = null;
    _params = null;
  }

  static Future<(CardSpec, VisionParams)> load() async {
    if (_cardSpec != null && _params != null) return (_cardSpec!, _params!);
    final specJson = await rootBundle.loadString(cardSpecPath);
    final paramsJson = await rootBundle.loadString(paramsPath);
    _cardSpec = CardSpec.fromJson((jsonDecode(specJson) as Map).cast<String, dynamic>());
    _params = VisionParams.fromJsonString(paramsJson);
    return (_cardSpec!, _params!);
  }
}
