import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/preventive_task.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Fase 0 (spec Horizontes): al egresar se CANCELAN las tareas AUTO pendientes
/// con fecha FUTURA de esa admisión (ya no hay ronda que las ejecute). Las
/// hechas, las saltadas, las manuales y las vencidas NO se tocan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('dischargePatient cancela solo las AUTO pendientes futuras', () async {
    final repo = await DataRepository.instance();
    final patient = repo.listAllPatients().first;
    final orgId = patient.organizationId;
    final now = DateTime.now();

    final adm = await repo.admitPatient(
      patientId: patient.id,
      organizationId: orgId,
    );

    // AUTO futura pendiente → debe quedar CANCELADA.
    final autoFuture = await repo.createPreventiveTask(
      patientId: patient.id,
      organizationId: orgId,
      title: 'Cambio de posición',
      scheduledAt: now.add(const Duration(hours: 4)),
      admissionId: adm.id,
      source: 'auto',
    );
    // AUTO vencida pendiente (pasada) → NO se toca (solo futuras).
    final autoPast = await repo.createPreventiveTask(
      patientId: patient.id,
      organizationId: orgId,
      title: 'Cambio de posición (vencida)',
      scheduledAt: now.subtract(const Duration(hours: 4)),
      admissionId: adm.id,
      source: 'auto',
    );
    // MANUAL futura pendiente → NO se toca (no es AUTO).
    final manualFuture = await repo.createPreventiveTask(
      patientId: patient.id,
      organizationId: orgId,
      title: 'Indicación manual',
      scheduledAt: now.add(const Duration(hours: 6)),
      admissionId: adm.id,
      source: 'manual',
    );
    // AUTO futura ya HECHA → NO se toca (es historia).
    final autoDone = await repo.createPreventiveTask(
      patientId: patient.id,
      organizationId: orgId,
      title: 'Ya realizada',
      scheduledAt: now.add(const Duration(hours: 2)),
      admissionId: adm.id,
      source: 'auto',
    );
    await repo.updatePreventiveTask(
        autoDone.id, {'status': PreventiveTaskStatus.done.dbValue});

    await repo.dischargePatient(adm.id);

    PreventiveTask reload(String id) =>
        repo.listPreventiveTasks(organizationId: orgId).firstWhere((t) => t.id == id);

    expect(reload(autoFuture.id).status, PreventiveTaskStatus.canceled);
    expect(reload(autoPast.id).status, PreventiveTaskStatus.pending);
    expect(reload(manualFuture.id).status, PreventiveTaskStatus.pending);
    expect(reload(autoDone.id).status, PreventiveTaskStatus.done);
  });
}
