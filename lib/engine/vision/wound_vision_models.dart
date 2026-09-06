import 'dart:typed_data';

import 'vision_geometry.dart';

/// Cómo se obtuvo la escala (px → mm).
enum CalibrationMode {
  /// Tarjeta WoundCalibrate (4 AprilTags): homografía completa, perspectiva corregida.
  card,

  /// Disco adhesivo de diámetro conocido: solo escala, sin corrección de perspectiva.
  disc,
}

extension CalibrationModeX on CalibrationMode {
  /// Valor persistido en `wound_measurements.measurement_source`.
  String get sourceValue => switch (this) {
        CalibrationMode.card => 'vision_card',
        CalibrationMode.disc => 'vision_disc',
      };

  String get label => switch (this) {
        CalibrationMode.card => 'Tarjeta de calibración',
        CalibrationMode.disc => 'Disco de referencia',
      };
}

/// Estado de una compuerta de calidad.
enum GateStatus { pass, warn, fail, skipped }

class QualityGate {
  final String id;
  final String label;
  final GateStatus status;
  final String detail;
  const QualityGate(this.id, this.label, this.status, this.detail);

  Map<String, dynamic> toJson() => {'id': id, 'status': status.name, 'detail': detail};
}

/// Resultado de la calibración: imagen rectificada (o reescalada, en modo
/// disco) + escala + compuertas. Los bytes PNG son lo único que la UI necesita
/// para dibujar; el raster vive en memoria solo durante la sesión de medición.
class CalibrationResult {
  final CalibrationMode mode;
  final double mmPerPx; // de la imagen rectificada
  final int width; // px rectificada
  final int height;
  final Uint8List rectifiedPng;

  /// Zonas que NO son herida por construcción (tarjeta o disco), en px rectificados.
  final List<RectD> excludedRects;

  /// Homografía foto original (px) → rectificada (px). Identidad+escala en modo disco.
  final Homography photoToRectified;
  final List<QualityGate> gates;
  final Map<String, dynamic> meta; // detalles numéricos para vision_meta

  const CalibrationResult({
    required this.mode,
    required this.mmPerPx,
    required this.width,
    required this.height,
    required this.rectifiedPng,
    required this.excludedRects,
    required this.photoToRectified,
    required this.gates,
    required this.meta,
  });

  bool get hasBlockingFailure => gates.any((g) => g.status == GateStatus.fail);
}

/// Fallo de calibración con motivo legible.
class CalibrationFailure {
  final String reason; // 'no_reference' | 'partial_tags' | 'decode_error'
  final String message;
  final int tagsFound;
  const CalibrationFailure(this.reason, this.message, {this.tagsFound = 0});
}

/// Porcentajes de tejido (suman 100). Claves iguales a los sliders del lecho.
class TissueComposition {
  final double granulacion;
  final double esfacelo;
  final double necrosis;
  final double epitelizacion;
  const TissueComposition({
    required this.granulacion,
    required this.esfacelo,
    required this.necrosis,
    required this.epitelizacion,
  });

  static const zero = TissueComposition(granulacion: 0, esfacelo: 0, necrosis: 0, epitelizacion: 0);

  Map<String, dynamic> toJson() => {
        'granulacion_pct': granulacion,
        'esfacelo_pct': esfacelo,
        'necrosis_pct': necrosis,
        'epitelizacion_pct': epitelizacion,
      };
}

/// Medidas geométricas en unidades clínicas.
class WoundMeasurementResult {
  final double areaCm2; // por conteo de píxeles (planimetría) — NO cambia
  // OFICIAL (convención de regla, ejes X/Y de la rectificada = marco de la
  // tarjeta): largo = extensión en X (borde LARGO de la tarjeta ∥ cabeza-pies),
  // ancho = extensión en Y (lateral). Alimentan ellipseArea/Kundin y area_cm2
  // (ver docs/engine/motor_vision.md).
  final double lengthCm; // extensión en el eje X (cabeza-pies)
  final double widthCm; // extensión en el eje Y (lateral)
  final double perimeterCm;
  final double ellipseEstimateCm2; // L × A × 0.785 (0.785 validado vs regla)
  // Feret máximo y su ancho perpendicular: dato ADICIONAL (vision_meta), nunca
  // la medida oficial. Sirve para inspección/QA, no para el expediente.
  final double feretLengthCm; // diámetro de Feret máximo (cualquier dirección)
  final double feretWidthCm; // extensión perpendicular al eje de Feret
  final Pt lengthA; // extremos del eje de largo (px rectificados)
  final Pt lengthB;
  final Pt widthA; // extremos del ancho (px rectificados)
  final Pt widthB;

  const WoundMeasurementResult({
    required this.areaCm2,
    required this.lengthCm,
    required this.widthCm,
    required this.perimeterCm,
    required this.ellipseEstimateCm2,
    required this.feretLengthCm,
    required this.feretWidthCm,
    required this.lengthA,
    required this.lengthB,
    required this.widthA,
    required this.widthB,
  });

  Map<String, dynamic> toJson() => {
        'area_cm2': areaCm2,
        'length_cm': lengthCm,
        'width_cm': widthCm,
        'perimeter_cm': perimeterCm,
        'ellipse_estimate_cm2': ellipseEstimateCm2,
        // Adicional, no oficial: Feret y su ancho perpendicular.
        'feret_length_cm': feretLengthCm,
        'feret_width_cm': feretWidthCm,
      };
}

/// Resultado completo de un análisis (segmentación + tejido + medidas).
class WoundVisionResult {
  final CalibrationResult calibration;
  final List<Pt> contourPx; // polígono simplificado, px rectificados
  final WoundMeasurementResult measurement;
  final TissueComposition tissue;
  final Uint8List overlayPng; // RGBA: contorno + tinte de tejido + ejes
  final List<QualityGate> gates; // compuertas de calibración + de la herida
  final String engineVersion;
  final bool manualTrace; // true si el contorno lo trazó el clínico (sin segmentación)

  const WoundVisionResult({
    required this.calibration,
    required this.contourPx,
    required this.measurement,
    required this.tissue,
    required this.overlayPng,
    required this.gates,
    required this.engineVersion,
    required this.manualTrace,
  });

  /// Valor para `wound_measurements.measurement_source`.
  String get measurementSource => manualTrace ? 'vision_manual_trace' : calibration.mode.sourceValue;

  /// JSON compacto para `wound_measurements.vision_meta` (auditoría/reproducibilidad).
  Map<String, dynamic> toVisionMeta() => {
        'engine_version': engineVersion,
        'mode': calibration.mode.name,
        'manual_trace': manualTrace,
        'mm_per_px': calibration.mmPerPx,
        'rectified_size': [calibration.width, calibration.height],
        'measurement': measurement.toJson(),
        'tissue': tissue.toJson(),
        'gates': [for (final g in gates) g.toJson()],
        'contour_px': [
          for (final p in contourPx) [double.parse(p.x.toStringAsFixed(1)), double.parse(p.y.toStringAsFixed(1))]
        ],
        'calibration': calibration.meta,
      };
}
