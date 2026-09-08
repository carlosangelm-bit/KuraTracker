import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/risk/prevention_risk_engine.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/demo_seed.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// Vigencia de escala (interino 8-sep-2026, pendiente de María): un resultado de
/// GLOBIAD vigente regenera su cuidado; VENCIDO (> validityHours) hace que el plan
/// pida REVALORAR en vez de seguir regenerando cuidado de un dato viejo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GLOBIAD vigente regenera cuidado; vencido pide revalorar', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    await DemoSeed.resetAndReseed(store);
    final repo = await DataRepository.forSeeding(LocalStoreDataStore(store));
    final catalog = await PreventionRulesCatalog.load();

    // Guadalupe trae una valoración GLOBIAD 2B de la semilla (assessed ~ahora).
    final g = store
        .getAll(Collections.patients)
        .firstWhere((p) => (p['full_name'] as String).contains('Guadalupe'));
    final pid = g['id'] as String;
    final orgId = g['organization_id'] as String?;

    Future<void> clearTasks() async {
      for (final t in store
          .getAll(Collections.preventiveTasks)
          .where((t) => t['patient_id'] == pid)
          .toList()) {
        await store.delete(Collections.preventiveTasks, t['id'] as String);
      }
    }

    bool has(String actionId) => store
        .getAll(Collections.preventiveTasks)
        .any((t) => t['patient_id'] == pid && t['action_id'] == actionId);

    // VIGENTE: generar poco después de la valoración → cuidado de GLOBIAD presente.
    await clearTasks();
    await repo.regeneratePreventivePlan(pid, catalog,
        organizationId: orgId, now: DateTime.now().add(const Duration(hours: 2)));
    expect(has('vigilancia_infeccion_dai'), isTrue,
        reason: 'GLOBIAD 2B vigente debe regenerar su vigilancia');
    expect(has('revalorar_globiad'), isFalse);

    // VENCIDO: 48 h después (vigencia GLOBIAD = 24 h) → revalorar, sin cuidado derivado.
    await clearTasks();
    await repo.regeneratePreventivePlan(pid, catalog,
        organizationId: orgId, now: DateTime.now().add(const Duration(hours: 48)));
    expect(has('revalorar_globiad'), isTrue,
        reason: 'GLOBIAD vencido debe pedir revalorar');
    expect(has('vigilancia_infeccion_dai'), isFalse,
        reason: 'no regenera cuidado de un resultado vencido');
  });
}
