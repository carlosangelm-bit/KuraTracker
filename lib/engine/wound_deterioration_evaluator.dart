import '../models/wound.dart';
import 'models/kura_engine_enums.dart';

/// Resultado de comparar dos consultas consecutivas (actual vs. la
/// inmediatamente anterior) para detectar deterioro objetivo de la
/// trayectoria clinica (kura_rules_v2, penalizacion de trayectoria del
/// checkpoint/kura_sheehan_checkpoint).
class WoundDeteriorationResult {
  final bool deterioroDelLecho;
  final bool aumentoDeExudado;
  final List<String> motivos;

  const WoundDeteriorationResult({
    required this.deterioroDelLecho,
    required this.aumentoDeExudado,
    required this.motivos,
  });

  static const none = WoundDeteriorationResult(
    deterioroDelLecho: false,
    aumentoDeExudado: false,
    motivos: [],
  );
}

/// Evalua "deterioro objetivo" (kura_rules_v2) comparando la medicion y
/// evaluacion de la consulta ACTUAL contra las de la consulta
/// INMEDIATAMENTE ANTERIOR (no contra la basal — esa comparacion ya la
/// hace KuraSheehanCheckpoint.evaluate() por separado para el % de
/// reduccion).
///
/// Se marca `deterioroDelLecho` si se cumple CUALQUIERA de:
/// - Tejido desvitalizado (necrosis + esfacelo) aumenta >10 puntos.
/// - Granulacion disminuye >=10 puntos.
/// - Area aumenta >10%.
/// - Desaparicion de epitelio (epitelizacion pasa de >0 a 0).
/// - Profundidad aumenta >0.5 cm.
/// - Bordes evertidos/macerados (wound_edge en {'macerado', 'epibole'} en
///   la consulta actual y no lo estaba en la anterior).
///
/// Ademas, por separado, `aumentoDeExudado` = true si la cantidad de
/// exudado sube >=1 nivel (ninguno < escaso < moderado < abundante)
/// respecto de la visita previa. Esto es "mala evolucion" pero se
/// mantiene como flag independiente (ya existe como parametro propio en
/// KuraSheehanCheckpoint.evaluate).
class WoundDeteriorationEvaluator {
  /// Bordes considerados evertidos/macerados en el campo de texto libre
  /// `wound_edge` (ver dropdowns de wound_capture_screen.dart y
  /// follow_up_capture_screen.dart: 'definido'/'irregular'/'dehiscente'/
  /// 'macerado'/'epibole'). No existe un valor literal "evertido" en el
  /// catalogo actual; "epibole" (borde enrollado/evertido) es el
  /// equivalente clinico mas cercano y se incluye junto con "macerado".
  static const _bordesDeRiesgo = {'macerado', 'epibole'};

  static WoundDeteriorationResult evaluate({
    required WoundMeasurement current,
    required WoundMeasurement previous,
    WoundAssessment? currentAssessment,
    WoundAssessment? previousAssessment,
  }) {
    final motivos = <String>[];

    final tejidoDesvitalizadoActual = current.necrosisPct + current.sloughPct;
    final tejidoDesvitalizadoPrevio = previous.necrosisPct + previous.sloughPct;
    if (tejidoDesvitalizadoActual - tejidoDesvitalizadoPrevio > 10) {
      motivos.add(
        'Tejido desvitalizado (necrosis+esfacelo) aumento '
        '${(tejidoDesvitalizadoActual - tejidoDesvitalizadoPrevio).toStringAsFixed(0)} '
        'puntos (>10).',
      );
    }

    if (previous.granulationPct - current.granulationPct >= 10) {
      motivos.add(
        'Granulacion disminuyo '
        '${(previous.granulationPct - current.granulationPct).toStringAsFixed(0)} '
        'puntos (>=10).',
      );
    }

    if (previous.areaCm2 > 0 &&
        ((current.areaCm2 - previous.areaCm2) / previous.areaCm2) * 100 > 10) {
      motivos.add('Area aumento '
          '${(((current.areaCm2 - previous.areaCm2) / previous.areaCm2) * 100).toStringAsFixed(0)}% '
          '(>10%).');
    }

    if (previous.epithelializationPct > 0 && current.epithelializationPct == 0) {
      motivos.add('Desaparicion de epitelio (epitelizacion pasa a 0%).');
    }

    if (current.depthCm - previous.depthCm > 0.5) {
      motivos.add(
        'Profundidad aumento ${(current.depthCm - previous.depthCm).toStringAsFixed(1)} cm '
        '(>0.5 cm).',
      );
    }

    final bordeActual = currentAssessment?.woundEdge;
    final bordePrevio = previousAssessment?.woundEdge;
    final bordeDeRiesgoAhora = bordeActual != null && _bordesDeRiesgo.contains(bordeActual);
    final bordeDeRiesgoAntes = bordePrevio != null && _bordesDeRiesgo.contains(bordePrevio);
    if (bordeDeRiesgoAhora && !bordeDeRiesgoAntes) {
      motivos.add('Bordes evertidos/macerados de nueva aparicion '
          '(${bordeActual == 'epibole' ? 'epibole' : bordeActual}).');
    }

    final deterioroDelLecho = motivos.isNotEmpty;

    bool aumentoDeExudado = false;
    final exudadoActual = currentAssessment?.exudateAmount;
    final exudadoPrevio = previousAssessment?.exudateAmount;
    if (exudadoActual != null && exudadoPrevio != null) {
      final nivelActual = ExudadoCantidad.values.indexOf(exudadoActual);
      final nivelPrevio = ExudadoCantidad.values.indexOf(exudadoPrevio);
      if (nivelActual - nivelPrevio >= 1) {
        aumentoDeExudado = true;
        motivos.add('Exudado aumento de ${exudadoPrevio.name} a ${exudadoActual.name} '
            '(>=1 nivel) vs. visita previa: mala evolucion.');
      }
    }

    return WoundDeteriorationResult(
      deterioroDelLecho: deterioroDelLecho,
      aumentoDeExudado: aumentoDeExudado,
      motivos: motivos,
    );
  }
}
