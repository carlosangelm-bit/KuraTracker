import '../../engine/kura_sheehan_checkpoint.dart';
import '../../engine/sheehan_decision_style.dart';
import '../../engine/wound_checkpoint_deriver.dart';
import '../../models/wound.dart';
import '../../services/data_repository.dart';

/// Estatus de trayectoria (checkpoint de Sheehan) de UNA herida activa,
/// usado como detalle por-herida en el tooltip del semaforo agregado del
/// paciente.
class WoundProgressStatus {
  final Wound wound;
  final ProgressStatus status;
  final SheehanCheckpointResult? checkpoint;

  const WoundProgressStatus({
    required this.wound,
    required this.status,
    required this.checkpoint,
  });
}

/// Semaforo de avance agregado por PACIENTE (punto 2 del rediseno): si el
/// paciente tiene varias heridas activas, se muestra el PEOR estatus
/// (rojo > amarillo > verde > sin datos), para que salte a la vista quien
/// necesita atencion. El detalle por herida queda disponible en
/// [byWound] para un tooltip que liste el estatus de cada una.
///
/// Reutiliza [WoundCheckpointDeriver] (misma derivacion que
/// follow_up_screen.dart) y [ProgressStatusFromDecision]/
/// [ProgressStatusStyle] (mismo mapeo color/etiqueta) -- no reinventa la
/// semantica del checkpoint de Sheehan.
class PatientProgressStatus {
  final ProgressStatus worst;
  final List<WoundProgressStatus> byWound;

  const PatientProgressStatus({required this.worst, required this.byWound});

  /// Prioridad de "peor" estatus: rojo > amarillo > verde > sin datos.
  static const List<ProgressStatus> _severityOrder = [
    ProgressStatus.danger,
    ProgressStatus.warning,
    ProgressStatus.good,
    ProgressStatus.noData,
  ];

  static PatientProgressStatus compute(DataRepository repo, List<Wound> activeWounds) {
    final byWound = activeWounds.map((w) {
      final checkpoint = WoundCheckpointDeriver.evaluate(repo, w);
      final status = checkpoint?.decision.toProgressStatus ?? ProgressStatus.noData;
      return WoundProgressStatus(wound: w, status: status, checkpoint: checkpoint);
    }).toList();

    ProgressStatus worst = ProgressStatus.noData;
    if (byWound.isNotEmpty) {
      worst = _severityOrder.firstWhere(
        (s) => byWound.any((w) => w.status == s),
        orElse: () => ProgressStatus.noData,
      );
    }

    return PatientProgressStatus(worst: worst, byWound: byWound);
  }
}
