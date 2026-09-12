import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/risk/prevention_risk_engine.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/demo_seed.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// Bug 1 (destapado por Fase B): re-generar el plan de LPP (al re-guardar el
/// Braden) NO debe borrar las tareas derivadas de una escala (GLOBIAD, etc.).
/// El generador de LPP ahora limpia SÓLO los ruleIds del catálogo (sus bandas),
/// no todo lo 'auto'. Cada apply*Treatment limpia sólo su propio ruleId.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('re-generar el plan NO borra una tarea PUNTUAL de escala (STAR)', () async {
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

    // STAR color comprometido → un EVENTO puntual (ruleId 'star'), que NO
    // pertenece al plan regenerable. Es lo que la limpieza consciente del ruleId
    // (Bug 1) debe proteger cuando se re-genera el plan por reglas + GLOBIAD.
    await repo.applyStarTreatment(pid, '3', organizationId: orgId);
    int countRule(String rule) => store
        .getAll(Collections.preventiveTasks)
        .where((t) => t['patient_id'] == pid && t['rule_id'] == rule)
        .length;
    expect(countRule('star'), greaterThan(0), reason: 'STAR debe crear su evento');

    // Re-valorar el Braden re-materializa el plan permanente (reglas + GLOBIAD)…
    await repo.autoGeneratePlanIfHospital(pid, catalog, organizationId: orgId);

    // …y el evento puntual de STAR sobrevive (Bug 1) y el plan permanente sigue.
    expect(countRule('star'), greaterThan(0),
        reason: 'Bug 1: re-generar el plan NO debe borrar la tarea puntual de STAR');
    expect(countRule('lpp_muy_alto'), greaterThan(0));
    expect(countRule('globiad'), greaterThan(0));
  });

  test('Bug 2 · control_humedad NO se duplica entre lpp_* y globiad (dedup cruzado)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    await DemoSeed.resetAndReseed(store);
    final repo = await DataRepository.forSeeding(LocalStoreDataStore(store));
    final catalog = await PreventionRulesCatalog.load();

    // Guadalupe (Braden 9 + GLOBIAD 2B): lpp_muy_alto pide control_humedad c/8h
    // y GLOBIAD también. El dedup cruzado deja UNA sola serie (3 en 24 h), no 6.
    final guadalupe = store
        .getAll(Collections.patients)
        .firstWhere((p) => (p['full_name'] as String).contains('Guadalupe'));
    final pid = guadalupe['id'] as String;

    final humedad = store
        .getAll(Collections.preventiveTasks)
        .where((t) => t['patient_id'] == pid && t['action_id'] == 'control_humedad')
        .toList();
    expect(humedad.length, 3,
        reason: 'control_humedad debe aparecer una sola vez (3 en 24 h), no 6');
    // La procedencia NO se persiste (nada en notes): se DERIVA en lectura.
    expect(humedad.every((t) => t['notes'] == null), isTrue,
        reason: 'la procedencia del dedup no se escribe en notes (documentación clínica)');
    final contribs = repo.contributingRuleIdsFor(pid, 'control_humedad', catalog);
    expect(contribs.contains('globiad'), isTrue);
    expect(contribs.any((r) => r.startsWith('lpp_')), isTrue,
        reason: 'la derivación en lectura muestra ambas fuentes (lpp_* y globiad)');
  });
}
