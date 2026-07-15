import 'package:flutter/material.dart';

import '../core/theme/kura_theme.dart';
import 'kura_sheehan_checkpoint.dart';

/// Semaforo de avance (trayectoria): las 3 decisiones del checkpoint de
/// Sheehan mas el estado "sin datos suficientes" (herida sin seguimiento
/// aun o con <2 mediciones). Un solo lugar para que follow_up_screen.dart
/// y las tarjetas/lista de pacientes usen exactamente la misma semantica
/// de color/icono/etiqueta (no reinventar, no duplicar).
enum ProgressStatus { good, warning, danger, noData }

extension ProgressStatusFromDecision on SheehanDecision {
  ProgressStatus get toProgressStatus {
    switch (this) {
      case SheehanDecision.confirmarCierre:
        return ProgressStatus.good;
      case SheehanDecision.extenderObservacion:
        return ProgressStatus.warning;
      case SheehanDecision.reclasificarC:
        return ProgressStatus.danger;
    }
  }
}

extension ProgressStatusStyle on ProgressStatus {
  /// Mapeo de color exigido por la especificacion:
  /// confirmarCierre -> verde (KuraColors.success)
  /// extenderObservacion -> amarillo (KuraColors.warning)
  /// reclasificarC -> rojo (KuraColors.danger)
  /// sin datos -> gris/neutral (no se fuerza un color del semaforo).
  Color get color {
    switch (this) {
      case ProgressStatus.good:
        return KuraColors.success;
      case ProgressStatus.warning:
        return KuraColors.warning;
      case ProgressStatus.danger:
        return KuraColors.danger;
      case ProgressStatus.noData:
        return KuraColors.darkText.withOpacity(0.38);
    }
  }

  /// Icono redundante al color (accesibilidad/daltonismo): el estatus
  /// nunca se comunica solo por color.
  IconData get icon {
    switch (this) {
      case ProgressStatus.good:
        return Icons.check_circle;
      case ProgressStatus.warning:
        return Icons.error_outline;
      case ProgressStatus.danger:
        return Icons.cancel;
      case ProgressStatus.noData:
        return Icons.remove_circle_outline;
    }
  }

  /// Etiqueta corta exigida por la especificacion.
  String get shortLabel {
    switch (this) {
      case ProgressStatus.good:
        return 'Avanza según lo esperado';
      case ProgressStatus.warning:
        return 'Avanza con reservas';
      case ProgressStatus.danger:
        return 'No avanza';
      case ProgressStatus.noData:
        return 'Sin seguimiento aún';
    }
  }

  static const _apoyoDisclaimer =
      'Apoyo a la decisión clínica, no un diagnóstico definitivo.';

  /// Texto ampliado para tooltip (punto 5 de la especificacion): deja
  /// explicito que refleja el checkpoint de Sheehan (% de reduccion real
  /// vs. el esperado por semana) y que es apoyo a la decision, no un
  /// juicio clinico definitivo.
  String tooltip({SheehanCheckpointResult? checkpoint}) {
    if (checkpoint == null) {
      return 'Sin datos suficientes para calcular la trayectoria de cierre '
          '(se necesitan al menos 2 mediciones). $_apoyoDisclaimer';
    }
    return '$shortLabel · Checkpoint de Sheehan (semana ${checkpoint.semana}): '
        'reducción ajustada ${checkpoint.pctReduccionAjustada.toStringAsFixed(1)}% '
        'vs. esperado ≥${checkpoint.umbralCierre.toStringAsFixed(0)}% para cierre, '
        '≥${checkpoint.umbralAlerta.toStringAsFixed(0)}% para continuar en '
        'observación. $_apoyoDisclaimer';
  }
}
