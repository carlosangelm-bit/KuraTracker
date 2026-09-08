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

  test('re-generar LPP conserva las tareas de GLOBIAD y barre la banda anterior', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    await DemoSeed.resetAndReseed(store);
    final repo = await DataRepository.forSeeding(LocalStoreDataStore(store));
    final catalog = await PreventionRulesCatalog.load();

    // Guadalupe: Braden 9 (muy_alto) + GLOBIAD 2B sembrado por la vía real.
    final guadalupe = store
        .getAll(Collections.patients)
        .firstWhere((p) => (p['full_name'] as String).contains('Guadalupe'));
    final pid = guadalupe['id'] as String;
    final orgId = guadalupe['organization_id'] as String?;

    int countRule(String rule) => store
        .getAll(Collections.preventiveTasks)
        .where((t) => t['patient_id'] == pid && t['rule_id'] == rule)
        .length;

    final globiadBefore = countRule('globiad');
    final lppBefore = countRule('lpp_muy_alto');
    expect(globiadBefore, greaterThan(0), reason: 'la semilla debe dejar tareas GLOBIAD');
    expect(lppBefore, greaterThan(0));

    // Re-valorar el Braden (mismo valor) → re-materializa el plan de LPP.
    await repo.autoGeneratePlanIfHospital(pid, catalog, organizationId: orgId);

    // Las tareas de GLOBIAD (vigilancia) sobreviven; las de LPP se regeneran.
    expect(countRule('globiad'), globiadBefore,
        reason: 'Bug 1: re-generar LPP NO debe borrar las tareas de GLOBIAD');
    expect(countRule('lpp_muy_alto'), lppBefore,
        reason: 'las tareas de LPP se regeneran sin duplicarse');
  });

  test('Bug 2 · control_humedad NO se duplica entre lpp_* y globiad (dedup cruzado)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    await DemoSeed.resetAndReseed(store);

    // Guadalupe (Braden 9 + GLOBIAD 2B): lpp_muy_alto pide control_humedad c/8h
    // y GLOBIAD también. El dedup cruzado deja UNA sola serie (3 en 24 h), no 6.
    final guadalupe = store
        .getAll(Collections.patients)
        .firstWhere((p) => (p['full_name'] as String).contains('Guadalupe'));
    final pid = guadalupe['id'];

    final humedad = store
        .getAll(Collections.preventiveTasks)
        .where((t) => t['patient_id'] == pid && t['action_id'] == 'control_humedad')
        .toList();
    expect(humedad.length, 3,
        reason: 'control_humedad debe aparecer una sola vez (3 en 24 h), no 6');
    // La justificación de la fuente perdedora (globiad) se conserva en notes.
    expect(humedad.every((t) => (t['notes'] as String? ?? '').contains('globiad')),
        isTrue,
        reason: 'la tarea fusionada debe conservar que GLOBIAD también la indica');
  });
}
