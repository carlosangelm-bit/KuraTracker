import '../../core/utils/wound_volume.dart';
import 'rasters.dart';
import 'vision_geometry.dart';
import 'wound_vision_models.dart';

/// Geometría clínica de la herida a partir de la máscara (o de un polígono
/// trazado a mano) en el espacio métrico de la imagen rectificada.
///
/// Convención de medidas (documentada en docs/engine/motor_vision.md):
///  - Área: planimetría = conteo de píxeles × (mm/px)². Es la medida "real"
///    frente al estimado manual L × A × 0,785.
///  - Largo: diámetro de Feret máximo (la mayor distancia entre dos puntos del
///    contorno), en cualquier dirección.
///  - Ancho: máxima extensión perpendicular al eje del largo.
///  - Perímetro: del polígono simplificado (Douglas–Peucker), que elimina la
///    sobreestimación en escalera del contorno de píxeles.
class WoundMeasurer {
  const WoundMeasurer._();

  /// Mide una máscara de trabajo. Devuelve el contorno en px RECTIFICADOS y las medidas.
  static (List<Pt>, WoundMeasurementResult)? measureMask(
    BitMask mask, {
    required double mmPerWorkPx,
    required Pt Function(Pt) toRectified,
    required double contourEpsilonPx,
  }) {
    final pixelCount = mask.count;
    if (pixelCount == 0) return null;
    final raw = mask.traceOuterContour();
    if (raw.length < 3) return null;
    final simplified = Poly.simplifyClosed(raw, contourEpsilonPx);
    final contourRect = [for (final p in simplified) toRectified(p)];
    final areaMm2 = pixelCount * mmPerWorkPx * mmPerWorkPx;
    final m = _measurePolygon(simplified, areaMm2Override: areaMm2, mmPerPx: mmPerWorkPx, toRectified: toRectified);
    return (contourRect, m);
  }

  /// Mide un polígono trazado a mano (px rectificados). El área es la del
  /// polígono (shoelace).
  static WoundMeasurementResult? measurePolygon(List<Pt> polygonRectPx, {required double mmPerRectPx}) {
    if (polygonRectPx.length < 3) return null;
    return _measurePolygon(polygonRectPx, mmPerPx: mmPerRectPx, toRectified: (p) => p);
  }

  static WoundMeasurementResult _measurePolygon(
    List<Pt> poly, {
    double? areaMm2Override,
    required double mmPerPx,
    required Pt Function(Pt) toRectified,
  }) {
    final areaMm2 = areaMm2Override ?? Poly.area(poly) * mmPerPx * mmPerPx;
    final perimeterMm = Poly.perimeter(poly) * mmPerPx;
    final hull = Poly.convexHull(poly);
    final (a, b, feret) = Poly.maxFeret(hull);
    final lengthMm = feret * mmPerPx;
    var widthMm = 0.0;
    var wa = a, wb = b;
    if (feret > 1e-9) {
      final axis = (b - a) * (1 / feret);
      final perp = axis.perp;
      final (mn, mx) = Poly.extentAlong(hull, perp);
      widthMm = (mx - mn) * mmPerPx;
      // Segmento de ancho dibujado por el centro del eje de largo.
      final mid = (a + b) * 0.5;
      final midT = mid.dot(perp);
      wa = mid + perp * (mn - midT);
      wb = mid + perp * (mx - midT);
    }
    final lengthCm = lengthMm / 10, widthCm = widthMm / 10;
    return WoundMeasurementResult(
      areaCm2: areaMm2 / 100,
      lengthCm: lengthCm,
      widthCm: widthCm,
      perimeterCm: perimeterMm / 10,
      ellipseEstimateCm2: WoundVolumeCalculator.ellipseArea(lengthCm, widthCm),
      lengthA: toRectified(a),
      lengthB: toRectified(b),
      widthA: toRectified(wa),
      widthB: toRectified(wb),
    );
  }
}
