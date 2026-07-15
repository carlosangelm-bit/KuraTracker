import '../models/wound.dart';
import '../services/data_repository.dart';
import 'kura_sheehan_checkpoint.dart';
import 'wound_deterioration_evaluator.dart';

/// Deriva el checkpoint de Sheehan de UNA herida, usando exactamente los
/// mismos insumos que ya usa follow_up_screen.dart (area basal + ultima
/// medicion + semana + penalizaciones de la evaluacion mas reciente, mas
/// deterioro/exudado calculados contra la consulta INMEDIATAMENTE ANTERIOR,
/// kura_rules_v2).
///
/// Punto unico de esta derivacion "wound -> SheehanCheckpointResult?" para
/// que la pantalla de seguimiento y el semaforo de avance de la lista de
/// pacientes (patient_progress_status.dart) usen exactamente la misma
/// logica -- no se reinventa ni se duplica.
///
/// Devuelve null cuando NO hay trayectoria calculable todavia: herida sin
/// ningun seguimiento registrado (solo la medicion basal) o con menos de
/// 2 mediciones en total. No se fuerza un checkpoint contra si misma.
class WoundCheckpointDeriver {
  /// Empata una medicion con su evaluacion clinica (misma consulta), con
  /// fallback a la evaluacion de fecha mas reciente si no hay
  /// consultation_id directo (dato legado). Misma regla que
  /// follow_up_screen.dart.
  static WoundAssessment? _matchAssessment(
    DataRepository repo,
    List<WoundAssessment> assessments,
    WoundMeasurement measurement,
  ) {
    final matching =
        assessments.where((a) => a.consultationId == measurement.consultationId).toList();
    if (matching.isNotEmpty) return matching.first;
    if (assessments.isEmpty) return null;
    final withDates = assessments
        .map((a) => (
              assessment: a,
              date: repo.getConsultation(a.consultationId)?.visitDate ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ))
        .toList()
      ..sort((x, y) => x.date.compareTo(y.date));
    return withDates.last.assessment;
  }

  static SheehanCheckpointResult? evaluate(DataRepository repo, Wound wound) {
    // listMeasurementsForWound ya devuelve la lista ordenada ascendente
    // por measured_at (ver DataRepository): basal = primera medicion,
    // actual = mas reciente.
    final measurements = repo.listMeasurementsForWound(wound.id);
    if (measurements.length < 2) return null;

    final baseline = measurements.first;
    final current = measurements.last;
    // Consulta inmediatamente anterior a la actual (NO la basal), para el
    // deterioro de trayectoria (kura_rules_v2). Si solo hay 2 mediciones,
    // "previous" coincide con "baseline".
    final previous = measurements[measurements.length - 2];
    final weeksSinceBaseline =
        current.measuredAt.difference(baseline.measuredAt).inDays ~/ 7;

    final assessments = repo.listAssessmentsForWound(wound.id);
    final latestAssessment = _matchAssessment(repo, assessments, current);
    final previousAssessment = _matchAssessment(repo, assessments, previous);

    final deterioro = WoundDeteriorationEvaluator.evaluate(
      current: current,
      previous: previous,
      currentAssessment: latestAssessment,
      previousAssessment: previousAssessment,
    );

    return KuraSheehanCheckpoint.evaluate(
      semana: weeksSinceBaseline.clamp(1, 52),
      areaBasalCm2: baseline.areaCm2,
      areaActualCm2: current.areaCm2,
      bajaAdherencia: latestAssessment?.lowAdherence ?? false,
      infeccionActiva: latestAssessment?.infectionCriteria.isNotEmpty ?? false,
      deterioroDelLecho: deterioro.deterioroDelLecho,
      aumentoDeExudado: deterioro.aumentoDeExudado,
    );
  }
}
