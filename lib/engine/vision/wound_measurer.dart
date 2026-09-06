import '../../core/utils/wound_volume.dart';
import 'rasters.dart';
import 'vision_geometry.dart';
import 'wound_vision_models.dart';

/// Geometría clínica de la herida a partir de la máscara (o de un polígono
/// trazado a mano) en el espacio métrico de la imagen rectificada.
///
/// Convención de medidas (documentada en docs/engine/motor_vision.md):
///  - Área (planimetría): conteo de píxeles × (mm/px)². Es la medida "real",
///    se guarda aparte (area_planimetric_cm2) y NO cambia con esta convención.
///  - Largo/Ancho OFICIALES: extensión en los ejes Y/X de la imagen rectificada
///    (marco de la tarjeta, alineada al eje cabeza-pies) — convención de REGLA.
///    Alimentan el estimado de elipse (L × A × 0,785, validado por María contra
///    regla) y por tanto area_cm2/Kundin. El Feret máximo y su ancho
///    perpendicular se guardan como dato adicional en vision_meta, nunca oficial.
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

    // MEDIDA OFICIAL — convención de regla en los ejes X/Y de la imagen
    // rectificada (marco métrico de la tarjeta). Por protocolo la tarjeta se
    // alinea con el eje cabeza-pies, así que Y = LARGO (cabeza-pies) y X = ANCHO
    // (lateral). Esto es lo que alimenta ellipseArea/Kundin y area_cm2, cuya
    // constante 0,785 María validó contra medidas de regla — no el Feret, que
    // corría el estimado ~2× (ver docs/engine/motor_vision.md). El toRectified
    // es escala+traslación (sin rotación), así que el bounding box en el espacio
    // de `poly` conserva los ejes del marco rectificado.
    var xMin = double.infinity, xMax = -double.infinity;
    var yMin = double.infinity, yMax = -double.infinity;
    for (final p in poly) {
      if (p.x < xMin) xMin = p.x;
      if (p.x > xMax) xMax = p.x;
      if (p.y < yMin) yMin = p.y;
      if (p.y > yMax) yMax = p.y;
    }
    final widthMm = (xMax - xMin) * mmPerPx; // X = ancho
    final lengthMm = (yMax - yMin) * mmPerPx; // Y = largo
    final xMid = (xMin + xMax) / 2, yMid = (yMin + yMax) / 2;
    final lengthA = toRectified(Pt(xMid, yMin)), lengthB = toRectified(Pt(xMid, yMax));
    final widthA = toRectified(Pt(xMin, yMid)), widthB = toRectified(Pt(xMax, yMid));

    // DATO ADICIONAL (vision_meta), NUNCA la medida oficial: Feret máximo (mayor
    // distancia entre dos puntos, en cualquier dirección) y su ancho
    // perpendicular. Útil para QA (p.ej. heridas muy oblicuas al eje del cuerpo).
    final (a, b, feret) = Poly.maxFeret(hull);
    final feretLengthMm = feret * mmPerPx;
    var feretWidthMm = 0.0;
    if (feret > 1e-9) {
      final axis = (b - a) * (1 / feret);
      final perp = axis.perp;
      final (mn, mx) = Poly.extentAlong(hull, perp);
      feretWidthMm = (mx - mn) * mmPerPx;
    }

    final lengthCm = lengthMm / 10, widthCm = widthMm / 10;
    return WoundMeasurementResult(
      areaCm2: areaMm2 / 100,
      lengthCm: lengthCm,
      widthCm: widthCm,
      perimeterCm: perimeterMm / 10,
      ellipseEstimateCm2: WoundVolumeCalculator.ellipseArea(lengthCm, widthCm),
      feretLengthCm: feretLengthMm / 10,
      feretWidthCm: feretWidthMm / 10,
      lengthA: lengthA,
      lengthB: lengthB,
      widthA: widthA,
      widthB: widthB,
    );
  }
}
