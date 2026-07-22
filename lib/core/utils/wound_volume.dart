/// Calculo de volumen de herida por la formula de Kundin (feat/volume-kundin-charts).
///
/// V (cm3) = Largo (cm) x Ancho (cm) x Profundidad (cm) x 0.327
///
/// La constante 0.327 es la de Kundin (elipsoide aplanado), la solicitada
/// explicitamente por el cliente para esta tarea. Si la profundidad es 0
/// o null (herida superficial, medida solo en 2D), el volumen no aplica:
/// se devuelve null en vez de forzar un 0 con significado clinico.
class WoundVolumeCalculator {
  const WoundVolumeCalculator._();

  static const double kundinConstant = 0.327;

  /// Constante de la elipse para el ÁREA 2D estimada (validada por María
  /// 2026-07): Área = Largo × Ancho × 0.785. Sustituye el estimado rectangular
  /// L×W. NOTA: el área alimenta el modelo pronóstico (logarea = log(1+área)),
  /// que fue calibrado con L×W; con este cambio las predicciones A/B/C se
  /// corren hasta recalibrar el modelo (decisión aceptada; validar con María).
  static const double ellipseAreaConstant = 0.785;

  /// Área 2D estimada por la fórmula de la elipse (0 si falta largo o ancho).
  static double ellipseArea(double lengthCm, double widthCm) {
    if (lengthCm <= 0 || widthCm <= 0) return 0;
    return lengthCm * widthCm * ellipseAreaConstant;
  }

  /// Devuelve el volumen auto-calculado por Kundin, o null si la
  /// profundidad es 0/null (herida superficial: el volumen 3D no aplica).
  static double? kundin({
    required double lengthCm,
    required double widthCm,
    required double? depthCm,
  }) {
    if (depthCm == null || depthCm <= 0) return null;
    if (lengthCm <= 0 || widthCm <= 0) return null;
    return lengthCm * widthCm * depthCm * kundinConstant;
  }

  /// Compara el volumen persistido contra el auto-calculo de Kundin para
  /// decidir el flag `volume_manual` al momento de guardar. Usa una
  /// tolerancia pequena para no marcar como "manual" diferencias de
  /// redondeo de punto flotante.
  static bool isManualOverride({
    required double? storedVolumeCm3,
    required double? autoCalculatedCm3,
  }) {
    if (storedVolumeCm3 == null && autoCalculatedCm3 == null) return false;
    if (storedVolumeCm3 == null || autoCalculatedCm3 == null) return true;
    return (storedVolumeCm3 - autoCalculatedCm3).abs() > 0.01;
  }
}
