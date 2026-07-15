import '../../engine/models/kura_engine_enums.dart';
import '../../models/wound.dart';
import '../../services/data_repository.dart';

/// Resumen de heridas ACTIVAS de un paciente, usado por ambas vistas
/// (lista y tarjeta) de [PatientsListScreen] y por [DashboardScreen] para
/// mostrar los chips de etiologia y para decidir la accion rapida de
/// "Seguimiento" (herida unica -> directo; varias -> selector; ninguna ->
/// boton deshabilitado).
///
/// Solo considera heridas con `is_active == true` -- una herida cerrada no
/// debe aparecer como chip ni ofrecerse como destino de seguimiento.
class PatientWoundSummary {
  final List<Wound> activeWounds;
  final List<Etiologia> etiologies;

  const PatientWoundSummary({required this.activeWounds, required this.etiologies});

  int get activeCount => activeWounds.length;
  bool get hasActiveWounds => activeWounds.isNotEmpty;

  static PatientWoundSummary compute(DataRepository repo, String patientId) {
    final activeWounds =
        repo.listWoundsForPatient(patientId).where((w) => w.isActive).toList();
    final etiologiesSeen = <Etiologia>{};
    for (final w in activeWounds) {
      etiologiesSeen.add(w.etiology);
    }
    return PatientWoundSummary(
      activeWounds: activeWounds,
      etiologies: etiologiesSeen.toList(),
    );
  }
}
