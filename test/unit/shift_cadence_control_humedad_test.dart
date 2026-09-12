import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/risk/prevention_risk_engine.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/demo_seed.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// Interino 8-sep-2026 (por investigación, pendiente de María):
///  - control_humedad SE AGREGA a lpp_bajo (Braden 15–18): el re-bandeo dejaba a
///    esos pacientes sin control de humedad; el protocolo LCRD lo pide también en
///    riesgo bajo.
///  - su cadencia es "una vez por turno" y sale de shift_config del centro
///    (perShift), no de un 8 h fijo: el default 8 h sólo aplica sin turnos.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('control_humedad en lpp_bajo, con cadencia resuelta desde el turno', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    await DemoSeed.resetAndReseed(store);
    final repo = await DataRepository.forSeeding(LocalStoreDataStore(store));
    final catalog = await PreventionRulesCatalog.load();

    // Héctor: Braden 15 → banda bajo (lpp_bajo) tras el re-bandeo.
    final hector = store
        .getAll(Collections.patients)
        .firstWhere((p) => (p['full_name'] as String).contains('Héctor'));
    final pid = hector['id'] as String;
    final orgId = hector['organization_id'] as String?;

    Future<void> clearTasks() async {
      for (final t in store
          .getAll(Collections.preventiveTasks)
          .where((t) => t['patient_id'] == pid)
          .toList()) {
        await store.delete(Collections.preventiveTasks, t['id'] as String);
      }
    }

    Future<void> setShift(int startHour, int endHour) async {
      final org = store
          .getAll(Collections.organizations)
          .firstWhere((o) => o['id'] == orgId);
      await store.upsert(Collections.organizations, {
        ...org,
        'shift_config': [
          {'name': 'Turno', 'startHour': startHour, 'endHour': endHour}
        ],
      });
    }

    int humedad() => store
        .getAll(Collections.preventiveTasks)
        .where((t) => t['patient_id'] == pid && t['action_id'] == 'control_humedad')
        .length;

    final t0 = DateTime(2026, 9, 8, 8, 0);

    // Turno de 8 h → control_humedad c/8 h → 3 en el horizonte de 24 h.
    await setShift(7, 15);
    await clearTasks();
    await repo.autoGeneratePlanIfHospital(pid, catalog, organizationId: orgId, now: t0);
    expect(humedad(), 3, reason: 'lpp_bajo debe incluir control_humedad (c/turno=8h → 3)');

    // Turno de 12 h → control_humedad c/12 h → 2. Prueba que sale del turno, no de 8h fijo.
    await setShift(7, 19);
    await clearTasks();
    await repo.autoGeneratePlanIfHospital(pid, catalog, organizationId: orgId, now: t0);
    expect(humedad(), 2, reason: 'la cadencia "por turno" se resuelve desde shift_config');
  });
}
