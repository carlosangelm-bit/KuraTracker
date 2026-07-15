import '../models/wound.dart';
import '../services/data_repository.dart';
import 'kura_sheehan_checkpoint.dart';

/// Deriva el checkpoint de Sheehan de UNA herida, usando exactamente los
/// mismos insumos que ya usa follow_up_screen.dart (area basal + ultima
/// medicion + semana + penalizaciones de la evaluacion mas reciente).
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
  static SheehanCheckpointResult? evaluate(DataRepository repo, Wound wound) {
    // listMeasurementsForWound ya devuelve la lista ordenada ascendente
    // por measured_at (ver DataRepository): basal = primera medicion,
    // actual = mas reciente.
    final measurements = repo.listMeasurementsForWound(wound.id);
    if (measurements.length < 2) return null;

    final baseline = measurements.first;
    final current = measurements.last;
    final weeksSinceBaseline =
        current.measuredAt.difference(baseline.measuredAt).inDays ~/ 7;

    // Evaluacion clinica de la visita mas reciente (la misma consulta de
    // `current`), para alimentar los flags de penalizacion del
    // checkpoint. Se empata por consultationId cuando es posible; si no
    // hay match directo (dato legado sin consultation_id), se cae a la
    // evaluacion cuya consulta tenga la fecha mas reciente. Misma regla
    // que follow_up_screen.dart.
    WoundAssessment? latestAssessment;
    final assessments = repo.listAssessmentsForWound(wound.id);
    final matching =
        assessments.where((a) => a.consultationId == current.consultationId).toList();
    if (matching.isNotEmpty) {
      latestAssessment = matching.first;
    } else if (assessments.isNotEmpty) {
      final withDates = assessments
          .map((a) => (
                assessment: a,
                date: repo.getConsultation(a.consultationId)?.visitDate ??
                    DateTime.fromMillisecondsSinceEpoch(0),
              ))
          .toList()
        ..sort((x, y) => x.date.compareTo(y.date));
      latestAssessment = withDates.last.assessment;
    }

    return KuraSheehanCheckpoint.evaluate(
      semana: weeksSinceBaseline.clamp(1, 52),
      areaBasalCm2: baseline.areaCm2,
      areaActualCm2: current.areaCm2,
      bajaAdherencia: latestAssessment?.lowAdherence ?? false,
      infeccionActiva: latestAssessment?.infectionCriteria.isNotEmpty ?? false,
      // deterioroDelLecho y aumentoDeExudado: TODO(clinico) pendiente,
      // igual que en follow_up_screen.dart -- no se inventa la regla.
    );
  }
}
