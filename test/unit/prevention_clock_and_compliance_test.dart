import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/risk/prevention_risk_engine.dart';
import 'package:kuratracker/models/preventive_task.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/demo_seed.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// C1: reloj inyectable + cumplimiento simulado por la vía real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reloj inyectable: el plan se agenda desde el `now` dado, determinista', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    await DemoSeed.resetAndReseed(store);
    final repo = await DataRepository.forSeeding(LocalStoreDataStore(store));
    final catalog = await PreventionRulesCatalog.load();

    final guadalupe = store
        .getAll(Collections.patients)
        .firstWhere((p) => (p['full_name'] as String).contains('Guadalupe'));
    final pid = guadalupe['id'] as String;
    final orgId = guadalupe['organization_id'] as String?;

    // Aislar el efecto del reloj: limpiar las tareas que dejó la semilla.
    for (final t in store
        .getAll(Collections.preventiveTasks)
        .where((t) => t['patient_id'] == pid)
        .toList()) {
      await store.delete(Collections.preventiveTasks, t['id'] as String);
    }

    final t0 = DateTime(2026, 9, 8, 12, 0, 0);
    await repo.autoGeneratePlanIfHospital(pid, catalog,
        organizationId: orgId, now: t0);

    final tasks = repo
        .listPreventiveTasks(patientId: pid)
        .where((t) => t.source == 'auto')
        .toList();
    expect(tasks, isNotEmpty);
    // Todas se agendan DESPUÉS del `now` dado (nunca en su pasado).
    expect(tasks.every((t) => t.scheduledAt.isAfter(t0)), isTrue);
    // La primera ocurrencia de cambios posturales (c/2h en muy_alto) es t0 + 2 h.
    final cambios = tasks
        .where((t) => t.actionId == 'cambios_2h_registro')
        .map((t) => t.scheduledAt)
        .toList()
      ..sort();
    expect(cambios.first, t0.add(const Duration(hours: 2)));

    // Determinista/idempotente: re-generar con el MISMO reloj no cambia el conteo.
    final before = repo.listPreventiveTasks(patientId: pid).length;
    await repo.autoGeneratePlanIfHospital(pid, catalog,
        organizationId: orgId, now: t0);
    expect(repo.listPreventiveTasks(patientId: pid).length, before);
  });

  test('cumplimiento simulado: hay tareas hechas y saltadas por la vía real', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    await DemoSeed.resetAndReseed(store);

    final hospitalOrg = store
        .getAll(Collections.patients)
        .firstWhere((p) =>
            (p['background_notes'] as String? ?? '').contains('Paciente hospitalizado'))['organization_id'];
    final tasks = store
        .getAll(Collections.preventiveTasks)
        .where((t) => t['organization_id'] == hospitalOrg)
        .map(PreventiveTask.fromJson)
        .toList();

    // La semilla generó el plan hace 12 h y completó/saltó algunas por la vía
    // real (no a mano): el panel de cumplimiento vuelve a tener un mix.
    expect(tasks.where((t) => t.status == PreventiveTaskStatus.done).isNotEmpty,
        isTrue,
        reason: 'debe haber tareas HECHAS (completePreventiveTask)');
    expect(tasks.where((t) => t.status == PreventiveTaskStatus.skipped).isNotEmpty,
        isTrue,
        reason: 'debe haber al menos una tarea SALTADA (skipPreventiveTask)');
    expect(tasks.where((t) => t.isPending).isNotEmpty, isTrue,
        reason: 'y tareas pendientes (vencidas sin hacer + futuras)');
  });
}
