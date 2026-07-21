import 'models/kura_engine_enums.dart';

/// Decision resultante del checkpoint de seguimiento (regla de Sheehan).
enum SheehanDecision {
  confirmarCierre, // reduccion cumple/supera umbral de cierre
  extenderObservacion, // reduccion entre umbral de alerta y de cierre
  reclasificarC, // reduccion por debajo del umbral de alerta (o penalizada)
}

extension SheehanDecisionLabel on SheehanDecision {
  String get label {
    switch (this) {
      case SheehanDecision.confirmarCierre:
        return 'Confirmar cierre (posible reclasificacion B -> A)';
      case SheehanDecision.extenderObservacion:
        return 'Extender observacion';
      case SheehanDecision.reclasificarC:
        return 'Reclasificar a C (contencion)';
    }
  }
}

/// Resultado del checkpoint de Sheehan para una visita de seguimiento.
class SheehanCheckpointResult {
  final int semana;
  final double areaBasalCm2;
  final double areaActualCm2;
  final double pctReduccionBruta; // sin penalizaciones
  final double pctReduccionAjustada; // con penalizaciones aplicadas
  final double umbralCierre;
  final double umbralAlerta;
  final SheehanDecision decision;
  final List<String> penalizacionesAplicadas;

  const SheehanCheckpointResult({
    required this.semana,
    required this.areaBasalCm2,
    required this.areaActualCm2,
    required this.pctReduccionBruta,
    required this.pctReduccionAjustada,
    required this.umbralCierre,
    required this.umbralAlerta,
    required this.decision,
    required this.penalizacionesAplicadas,
  });
}

/// Checkpoint de seguimiento (regla de Sheehan) — seccion 8.5.
///
/// Compara area actual vs area basal en visitas de seguimiento, aplica
/// penalizaciones por infeccion activa, baja adherencia, deterioro del
/// lecho y aumento de exudado, y decide contra umbrales por semana.
class KuraSheehanCheckpoint {
  /// Umbrales oficiales por semana segun especificacion (semana 4 es la
  /// regla validada: 50% cierre / 30% alerta). Semanas intermedias no
  /// listadas se interpolan linealmente entre los puntos conocidos; fuera
  /// del rango se usa el valor del extremo mas cercano.
  static const Map<int, ({double cierre, double alerta})> _umbralesOficiales = {
    2: (cierre: 30, alerta: 15),
    4: (cierre: 50, alerta: 30),
    6: (cierre: 65, alerta: 45),
    8: (cierre: 75, alerta: 60),
  };

  /// Hitos de cicatrización esperada POR ETIOLOGÍA (Protocolos "etiologías" /
  /// Sheehan): semana de control y % de reducción de área esperado en ella.
  ///   - Pie diabético (UPD): 8 semanas / 50%.
  ///   - Vascular (MMII):      4 semanas / 40%.
  ///   - LPP:                  8 semanas / 50%.
  ///   - Quirúrgica:           4 semanas / 50%.
  /// Etiologías sin hito propio (traumática/otra) usan la tabla genérica.
  static const Map<Etiologia, ({int semanaHito, double pctCierre})>
      _hitosPorEtiologia = {
    Etiologia.pieDiabetico: (semanaHito: 8, pctCierre: 50),
    Etiologia.vascular: (semanaHito: 4, pctCierre: 40),
    Etiologia.lpp: (semanaHito: 8, pctCierre: 50),
    Etiologia.quirurgica: (semanaHito: 4, pctCierre: 50),
  };

  /// Razón umbral de alerta respecto al de cierre (documentada, ajustable):
  /// 0.6, consistente con la tabla genérica en semana 4 (30/50).
  static const double _ratioAlerta = 0.6;

  static ({int semanaHito, double pctCierre})? hitoParaEtiologia(
          Etiologia etiologia) =>
      _hitosPorEtiologia[etiologia];

  /// Umbrales (cierre/alerta) para una etiología y semana dadas. El % de
  /// cierre esperado escala linealmente de 0 (semana 0) al % del hito en su
  /// semana de control, y se mantiene plano después; el de alerta es
  /// [_ratioAlerta] del de cierre. Si la etiología no tiene hito propio, se
  /// usa la tabla genérica por semana.
  static ({double cierre, double alerta}) umbralesParaEtiologiaYSemana(
      Etiologia etiologia, int semana) {
    final hito = _hitosPorEtiologia[etiologia];
    if (hito == null) return umbralesParaSemana(semana);
    final ramp = (semana / hito.semanaHito).clamp(0.0, 1.0);
    final cierre = hito.pctCierre * ramp;
    return (cierre: cierre, alerta: cierre * _ratioAlerta);
  }

  static ({double cierre, double alerta}) umbralesParaSemana(int semana) {
    final keys = _umbralesOficiales.keys.toList()..sort();
    if (_umbralesOficiales.containsKey(semana)) {
      return _umbralesOficiales[semana]!;
    }
    if (semana <= keys.first) return _umbralesOficiales[keys.first]!;
    if (semana >= keys.last) return _umbralesOficiales[keys.last]!;
    // Interpolacion lineal entre los dos puntos mas cercanos.
    int lower = keys.first;
    int upper = keys.last;
    for (var i = 0; i < keys.length - 1; i++) {
      if (semana >= keys[i] && semana <= keys[i + 1]) {
        lower = keys[i];
        upper = keys[i + 1];
        break;
      }
    }
    final t = (semana - lower) / (upper - lower);
    final cLower = _umbralesOficiales[lower]!;
    final cUpper = _umbralesOficiales[upper]!;
    return (
      cierre: cLower.cierre + t * (cUpper.cierre - cLower.cierre),
      alerta: cLower.alerta + t * (cUpper.alerta - cLower.alerta),
    );
  }

  /// Evalua el checkpoint. Las penalizaciones reducen el % de reduccion
  /// ajustado (en puntos porcentuales) antes de comparar contra umbrales.
  /// Cada penalizacion activa resta 5 puntos porcentuales (criterio de
  /// severidad conservador, documentado y ajustable).
  static SheehanCheckpointResult evaluate({
    required int semana,
    required double areaBasalCm2,
    required double areaActualCm2,
    Etiologia? etiologia,
    bool infeccionActiva = false,
    bool bajaAdherencia = false,
    bool deterioroDelLecho = false,
    bool aumentoDeExudado = false,
    double penalizacionPorFactor = 5.0,
  }) {
    // Con etiología: umbrales por hito de etiología (Prompt 4); sin ella, la
    // tabla genérica por semana (comportamiento histórico).
    final umbrales = etiologia != null
        ? umbralesParaEtiologiaYSemana(etiologia, semana)
        : umbralesParaSemana(semana);

    double pctReduccionBruta;
    if (areaBasalCm2 <= 0) {
      pctReduccionBruta = 0.0;
    } else {
      pctReduccionBruta = ((areaBasalCm2 - areaActualCm2) / areaBasalCm2) * 100.0;
    }

    final penalizaciones = <String>[];
    double penalizacionTotal = 0.0;
    if (infeccionActiva) {
      penalizaciones.add('Infeccion activa');
      penalizacionTotal += penalizacionPorFactor;
    }
    if (bajaAdherencia) {
      penalizaciones.add('Baja adherencia al tratamiento');
      penalizacionTotal += penalizacionPorFactor;
    }
    if (deterioroDelLecho) {
      penalizaciones.add('Deterioro del lecho de la herida');
      penalizacionTotal += penalizacionPorFactor;
    }
    if (aumentoDeExudado) {
      penalizaciones.add('Aumento del exudado');
      penalizacionTotal += penalizacionPorFactor;
    }

    final pctReduccionAjustada = pctReduccionBruta - penalizacionTotal;

    SheehanDecision decision;
    if (pctReduccionAjustada >= umbrales.cierre) {
      decision = SheehanDecision.confirmarCierre;
    } else if (pctReduccionAjustada >= umbrales.alerta) {
      decision = SheehanDecision.extenderObservacion;
    } else {
      decision = SheehanDecision.reclasificarC;
    }

    return SheehanCheckpointResult(
      semana: semana,
      areaBasalCm2: areaBasalCm2,
      areaActualCm2: areaActualCm2,
      pctReduccionBruta: pctReduccionBruta,
      pctReduccionAjustada: pctReduccionAjustada,
      umbralCierre: umbrales.cierre,
      umbralAlerta: umbrales.alerta,
      decision: decision,
      penalizacionesAplicadas: penalizaciones,
    );
  }
}
