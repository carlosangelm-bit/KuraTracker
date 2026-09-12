import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/engine/risk/prevention_risk_engine.dart';

/// Hueco 2: la acción postural del plan sale del MAPEO banda→acción de las reglas
/// (fuente única), no de una escalera de cortes propia. Este test fija el mapeo
/// actual (pre-Fase C); cuando C2 re-bandee, estos valores se actualizan aquí y
/// en prevention_rules.json a la vez — que es justo el punto: un solo lugar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('posturalActionForBraden coincide con las bandas de prevention_rules.json', () async {
    final catalog = await PreventionRulesCatalog.load();

    // Post re-bandeo Fase C (5 bandas): moderado 13–14, bajo 15–18, sin_riesgo 19–23.
    expect(catalog.posturalActionForBraden(8), 'cambios_2h_registro'); // muy_alto 6–9
    expect(catalog.posturalActionForBraden(11), 'cambios_2h_registro'); // alto 10–12
    expect(catalog.posturalActionForBraden(13), 'cambios_2_3h'); // moderado 13–14
    expect(catalog.posturalActionForBraden(15), 'cambios_4h'); // bajo 15–18
    expect(catalog.posturalActionForBraden(19), isNull); // sin_riesgo 19–23: sin regla
    expect(catalog.posturalActionForBraden(24), isNull); // fuera de rango

  });
}
