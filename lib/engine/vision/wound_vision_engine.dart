import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'rasters.dart';
import 'reference_calibrator.dart';
import 'tissue_classifier.dart';
import 'vision_geometry.dart';
import 'vision_params.dart';
import 'wound_measurer.dart';
import 'wound_segmenter.dart';
import 'wound_vision_models.dart';

export 'reference_calibrator.dart' show CalibrationOutcome;
export 'wound_vision_models.dart';

/// Motor de medición y clasificación de heridas a partir de una fotografía.
///
/// Dart puro (sin plugins nativos): corre en Flutter Web, iOS y Android; las
/// fotos NO salen del dispositivo. Flujo en dos pasos, pensado para la UI:
///
///  1. [calibratePhoto]: decodifica la foto, localiza la referencia física
///     (tarjeta WoundCalibrate o disco), corrige perspectiva y devuelve la
///     imagen rectificada con su escala (mm/px) y compuertas de calidad.
///  2. [analyze]: con uno o más toques del clínico DENTRO de la herida,
///     segmenta, clasifica el tejido y mide (área, largo, ancho, perímetro).
///     [analyzeManualTrace] hace lo mismo con un contorno trazado a mano.
///
/// El resultado es APOYO a la decisión clínica: la UI debe permitir revisar y
/// editar cada valor antes de guardarlo (misma etiqueta que el resto del
/// motor Kura+: "no sustituye el juicio clínico").
class WoundVisionEngine {
  final CardSpec spec;
  final VisionParams params;
  final WoundSegmenter segmenter;
  final TissueClassifier classifier;
  late final ReferenceCalibrator _calibrator = ReferenceCalibrator(spec: spec, params: params);

  WoundVisionEngine({
    required this.spec,
    required this.params,
    WoundSegmenter? segmenter,
    TissueClassifier? classifier,
  })  : segmenter = segmenter ?? ColorRegionSegmenter(params),
        classifier = classifier ?? RuleTissueClassifier(params);

  /// Versión del motor que viaja en `vision_meta` (algoritmo + parámetros).
  static const algorithmVersion = 'kura-vision/1.0';

  String get engineVersion => '$algorithmVersion+${params.tissueRules.length}r';

  // ---------------------------------------------------------------------------
  // Paso 1: calibración
  // ---------------------------------------------------------------------------

  /// Decodifica [imageBytes] (JPEG/PNG; respeta la orientación EXIF) y calibra.
  CalibrationOutcome calibratePhoto(Uint8List imageBytes, {bool preferDisc = false}) {
    final raster = decodePhoto(imageBytes);
    if (raster == null) {
      return const CalibrationOutcome.fail(
          CalibrationFailure('decode_error', 'No se pudo leer la imagen (formato no soportado).'));
    }
    return _calibrator.calibrate(raster, preferDisc: preferDisc);
  }

  /// Igual que [calibratePhoto] pero a partir de un raster ya decodificado.
  CalibrationOutcome calibratePhotoRaster(RgbRaster raster, {bool preferDisc = false}) =>
      _calibrator.calibrate(raster, preferDisc: preferDisc);

  /// Decodifica a raster RGB aplicando la orientación EXIF. null si falla.
  static RgbRaster? decodePhoto(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    img.Image image = decoded;
    try {
      image = img.bakeOrientation(decoded);
    } catch (_) {
      // Sin EXIF utilizable: usar la imagen tal cual.
    }
    // Normalizar a 8 bits/canal RGB (p. ej. PNG de 16 bits o con alfa).
    if (image.format != img.Format.uint8 || image.numChannels != 3) {
      image = image.convert(format: img.Format.uint8, numChannels: 3);
    }
    return RgbRaster.fromImage(image);
  }

  /// Reconstruye el raster rectificado desde el PNG del resultado (para cuando
  /// la calibración y el análisis ocurren en procesos/isolates distintos).
  static RgbRaster? decodeRectified(CalibrationResult cal) {
    final image = img.decodePng(cal.rectifiedPng);
    return image == null ? null : RgbRaster.fromImage(image);
  }

  // ---------------------------------------------------------------------------
  // Paso 2: análisis
  // ---------------------------------------------------------------------------

  /// Segmenta desde [seeds] (px rectificados), clasifica el tejido y mide.
  /// Devuelve null si no se pudo delimitar una región (semillas fuera de la
  /// zona útil o región vacía).
  WoundVisionResult? analyze(
    CalibrationOutcome cal, {
    required List<Pt> seeds,
    RectD? roi,
    double? sensitivity,
  }) {
    final result = cal.result;
    if (result == null) return null;
    final rect = cal.rectified ?? decodeRectified(result);
    if (rect == null) return null;
    final valid = cal.valid ?? BitMask.filled(rect.width, rect.height, true);

    final seg = segmenter.segment(SegmentationRequest(
      rectified: rect,
      valid: valid,
      excludedRects: result.excludedRects,
      seeds: seeds,
      roi: roi,
      sensitivity: sensitivity ?? params.sensitivityDefault,
    ));
    if (seg == null) return null;

    final tissue = classifier.classify(seg.work, seg.mask);
    final measured = WoundMeasurer.measureMask(
      seg.mask,
      mmPerWorkPx: seg.mmPerWorkPx(result.mmPerPx),
      toRectified: seg.toRectified,
      contourEpsilonPx: params.contourEpsilonPx,
    );
    if (measured == null) return null;
    final (contour, measurement) = measured;

    final gates = [
      ...result.gates,
      _overexposureGate(rect, seg.mask, seg.factor, seg.offsetX, seg.offsetY),
    ];
    final overlay = _renderOverlay(
      width: rect.width,
      height: rect.height,
      contour: contour,
      measurement: measurement,
      tissueLabels: tissue.labels,
      tissueMask: seg.mask,
      factor: seg.factor,
      offsetX: seg.offsetX,
      offsetY: seg.offsetY,
      roi: seg.roi,
    );
    return WoundVisionResult(
      calibration: result,
      contourPx: contour,
      measurement: measurement,
      tissue: tissue.composition,
      overlayPng: overlay,
      gates: gates,
      engineVersion: engineVersion,
      manualTrace: false,
    );
  }

  /// Contorno trazado a mano por el clínico (px rectificados, ≥ 3 puntos):
  /// se mide el polígono y se clasifica el tejido dentro de él.
  WoundVisionResult? analyzeManualTrace(CalibrationOutcome cal, {required List<Pt> polygon}) {
    final result = cal.result;
    if (result == null || polygon.length < 3) return null;
    final rect = cal.rectified ?? decodeRectified(result);
    if (rect == null) return null;

    final measurement = WoundMeasurer.measurePolygon(polygon, mmPerRectPx: result.mmPerPx);
    if (measurement == null) return null;

    // Rasterizar el polígono dentro de su caja para clasificar el tejido.
    var minX = rect.width.toDouble(), minY = rect.height.toDouble(), maxX = 0.0, maxY = 0.0;
    for (final p in polygon) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final x0 = minX.floor().clamp(0, rect.width - 1), y0 = minY.floor().clamp(0, rect.height - 1);
    final x1 = (maxX.ceil() + 1).clamp(x0 + 1, rect.width), y1 = (maxY.ceil() + 1).clamp(y0 + 1, rect.height);
    final f = math.max(1, (math.max(x1 - x0, y1 - y0) / params.workMaxSidePx).ceil());
    final cw = math.max(f, ((x1 - x0) ~/ f) * f), ch = math.max(f, ((y1 - y0) ~/ f) * f);
    final work = rect.crop(x0, y0, math.min(cw, rect.width - x0), math.min(ch, rect.height - y0)).downscale(f);
    final mask = _rasterizePolygon(
      [for (final p in polygon) Pt((p.x - x0) / f, (p.y - y0) / f)],
      work.width,
      work.height,
    );
    final tissue = classifier.classify(work, mask);
    final overlay = _renderOverlay(
      width: rect.width,
      height: rect.height,
      contour: polygon,
      measurement: measurement,
      tissueLabels: tissue.labels,
      tissueMask: mask,
      factor: f,
      offsetX: x0,
      offsetY: y0,
      roi: null,
    );
    return WoundVisionResult(
      calibration: result,
      contourPx: polygon,
      measurement: measurement,
      tissue: tissue.composition,
      overlayPng: overlay,
      gates: [
        ...result.gates,
        _overexposureGate(rect, mask, f, x0, y0),
        const QualityGate('manual_trace', 'Contorno', GateStatus.warn, 'Contorno trazado a mano por el clínico'),
      ],
      engineVersion: engineVersion,
      manualTrace: true,
    );
  }

  // ---------------------------------------------------------------------------

  QualityGate _overexposureGate(RgbRaster rect, BitMask mask, int f, int ox, int oy) {
    var burnt = 0, total = 0;
    final thr = params.overexposedThreshold;
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        if (mask.data[y * mask.width + x] == 0) continue;
        final gx = (ox + x * f).clamp(0, rect.width - 1), gy = (oy + y * f).clamp(0, rect.height - 1);
        total++;
        if (rect.r(gx, gy) >= thr && rect.g(gx, gy) >= thr && rect.b(gx, gy) >= thr) burnt++;
      }
    }
    final frac = total == 0 ? 0.0 : burnt / total;
    final ok = frac <= params.overexposedMaxFraction;
    return QualityGate(
      'exposure',
      'Exposición de la herida',
      ok ? GateStatus.pass : GateStatus.warn,
      ok
          ? 'Sin zonas quemadas (${(frac * 100).toStringAsFixed(1)} %)'
          : '${(frac * 100).toStringAsFixed(1)} % de la herida está sobreexpuesta: evita el flash directo',
    );
  }

  /// Relleno por paridad (scanline) de un polígono en una máscara.
  static BitMask _rasterizePolygon(List<Pt> poly, int w, int h) {
    final mask = BitMask(w, h);
    final n = poly.length;
    for (var y = 0; y < h; y++) {
      final sy = y + 0.5;
      final xs = <double>[];
      for (var i = 0; i < n; i++) {
        final a = poly[i], b = poly[(i + 1) % n];
        if ((a.y <= sy && b.y > sy) || (b.y <= sy && a.y > sy)) {
          xs.add(a.x + (sy - a.y) * (b.x - a.x) / (b.y - a.y));
        }
      }
      xs.sort();
      for (var i = 0; i + 1 < xs.length; i += 2) {
        final xa = xs[i].round().clamp(0, w), xb = xs[i + 1].round().clamp(0, w);
        if (xb > xa) mask.data.fillRange(y * w + xa, y * w + xb, 1);
      }
    }
    return mask;
  }

  // Colores de tejido (espejo de KuraTissueColors; el motor no depende de Flutter).
  static const _tissueRgb = <List<int>>[
    [0xB5, 0x46, 0x3C], // granulación
    [0xD8, 0xB2, 0x4A], // esfacelo
    [0x2B, 0x2B, 0x2B], // necrosis
    [0xE7, 0x9A, 0xAE], // epitelización
  ];

  /// Capa RGBA (mismo tamaño que la rectificada): tinte de tejido, contorno,
  /// ejes de largo/ancho y, opcionalmente, el ROI.
  static Uint8List _renderOverlay({
    required int width,
    required int height,
    required List<Pt> contour,
    required WoundMeasurementResult measurement,
    required Uint8List tissueLabels,
    required BitMask tissueMask,
    required int factor,
    required int offsetX,
    required int offsetY,
    required RectD? roi,
  }) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    // Tinte de tejido (alfa 120) — cada píxel de trabajo cubre factor×factor.
    for (var y = 0; y < tissueMask.height; y++) {
      for (var x = 0; x < tissueMask.width; x++) {
        final cls = tissueLabels[y * tissueMask.width + x];
        if (cls > 3) continue;
        final c = _tissueRgb[cls];
        for (var dy = 0; dy < factor; dy++) {
          final gy = offsetY + y * factor + dy;
          if (gy < 0 || gy >= height) continue;
          for (var dx = 0; dx < factor; dx++) {
            final gx = offsetX + x * factor + dx;
            if (gx < 0 || gx >= width) continue;
            image.setPixelRgba(gx, gy, c[0], c[1], c[2], 120);
          }
        }
      }
    }
    if (roi != null) {
      final roiColor = img.ColorRgba8(0x7C, 0x3A, 0xED, 90);
      img.drawLine(image, x1: roi.x0.round(), y1: roi.y0.round(), x2: roi.x1.round(), y2: roi.y0.round(), color: roiColor);
      img.drawLine(image, x1: roi.x1.round(), y1: roi.y0.round(), x2: roi.x1.round(), y2: roi.y1.round(), color: roiColor);
      img.drawLine(image, x1: roi.x1.round(), y1: roi.y1.round(), x2: roi.x0.round(), y2: roi.y1.round(), color: roiColor);
      img.drawLine(image, x1: roi.x0.round(), y1: roi.y1.round(), x2: roi.x0.round(), y2: roi.y0.round(), color: roiColor);
    }
    final contourColor = img.ColorRgba8(255, 255, 255, 235);
    for (var i = 0; i < contour.length; i++) {
      final a = contour[i], b = contour[(i + 1) % contour.length];
      img.drawLine(image,
          x1: a.x.round(), y1: a.y.round(), x2: b.x.round(), y2: b.y.round(), color: contourColor, thickness: 2);
    }
    final axisColor = img.ColorRgba8(0x7C, 0x3A, 0xED, 230);
    img.drawLine(image,
        x1: measurement.lengthA.x.round(),
        y1: measurement.lengthA.y.round(),
        x2: measurement.lengthB.x.round(),
        y2: measurement.lengthB.y.round(),
        color: axisColor,
        thickness: 2);
    img.drawLine(image,
        x1: measurement.widthA.x.round(),
        y1: measurement.widthA.y.round(),
        x2: measurement.widthB.x.round(),
        y2: measurement.widthB.y.round(),
        color: axisColor,
        thickness: 2);
    for (final p in [measurement.lengthA, measurement.lengthB, measurement.widthA, measurement.widthB]) {
      img.fillCircle(image, x: p.x.round(), y: p.y.round(), radius: 3, color: axisColor);
    }
    return img.encodePng(image, level: 3);
  }
}
