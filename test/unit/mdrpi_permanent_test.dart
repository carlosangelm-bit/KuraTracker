import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/risk/prevention_risk_engine.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/demo_seed.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// Interino 8-sep-2026: MDRPI pasa de tarea PUNTUAL (una inspección a +8 h, título
/// "por turno") a PERMANENTE — inspección del sitio del dispositivo CADA 4 H
/// mientras el dispositivo esté puesto —, materializada por el regenerador.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MDRPI: inspeccion_dispositivo c/4h, sobrevive re-gen de LPP, título corregido', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    await DemoSeed.resetAndReseed(store);
    final repo = await DataRepository.forSeeding(LocalStoreDataStore(store));
    final catalog = await PreventionRulesCatalog.load();

    final p = store.getAll(Collections.patients).firstWhere(
        (p) => (p['full_name'] as String).contains('Héctor'));
    final pid = p['id'] as String;
    final orgId = p['organization_id'] as String?;

    for (final t in store
        .getAll(Collections.preventiveTasks)
        .where((t) => t['patient_id'] == pid)
        .toList()) {
      await store.delete(Collections.preventiveTasks, t['id'] as String);
    }

    // Captura MDRPI por la vía real y regenera cerca de la valoración (vigente).
    await repo.addScaleAssessment(
        patientId: pid, organizationId: orgId, scaleId: 'MDRPI',
        categoryResult: '1', staffId: null);
    final t0 = DateTime.now().add(const Duration(hours: 1));
    await repo.regeneratePreventivePlan(pid, catalog, organizationId: orgId, now: t0);

    List<Map<String, dynamic>> insp() => store
        .getAll(Collections.preventiveTasks)
        .where((t) => t['patient_id'] == pid && t['action_id'] == 'inspeccion_dispositivo')
        .toList();

    expect(insp().length, 6, reason: 'c/4 h en horizonte 24 h → 6 (permanente, no una)');
    expect(insp().first['action_label'], contains('cada 4 h'),
        reason: 'título corregido: ya no dice "por turno"');
    expect(insp().every((t) => t['rule_id'] == 'mdrpi'), isTrue);

    // Re-generar el plan (reglas + escalas permanentes) mantiene la inspección.
    await repo.autoGeneratePlanIfHospital(pid, catalog, organizationId: orgId, now: t0);
    expect(insp().length, 6, reason: 'MDRPI permanente se regenera, no se pierde');
  });
}
