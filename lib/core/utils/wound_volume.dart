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
