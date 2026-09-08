import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/engine/risk/braden_scale.dart';
import 'package:kuratracker/engine/risk/prevention_risk_engine.dart';
import 'package:kuratracker/features/risk/risk_board_screen.dart'
    show effectiveRiskLevel, bradenBandLevel;

/// Reja del bug merge-blocker de C2/C3: la banda de Braden NO puede enmascarar
/// una alerta más grave en el tablero de triage. Antes, `bradenBandLevel(20) ??
/// alertas` cortaba en corto y un Braden 20 con EAP (alerta ALTA) salía "sin
/// riesgo". Un refactor futuro que reintroduzca ese `??` debe poner esto en rojo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Braden 20 (banda sin_riesgo) + alerta ALTA → nivel efectivo ALTO', () async {
    await BradenScale.load(); // popula la caché que usa bradenBandLevel
    // Braden 20 cae en la banda sin_riesgo (tras el re-bandeo de Fase C)…
    expect(bradenBandLevel(20), RiskLevel.sinRiesgo);
    // …pero con una alerta ALTA (p.ej. complic_eap_isquemia), el nivel efectivo
    // es ALTO — la banda NO enmascara la alerta.
    expect(effectiveRiskLevel(bradenBandLevel(20), RiskLevel.alto), RiskLevel.alto);
  });

  test('effectiveRiskLevel = mayor severidad (nunca ??)', () {
    expect(effectiveRiskLevel(RiskLevel.sinRiesgo, RiskLevel.alto), RiskLevel.alto);
    expect(effectiveRiskLevel(RiskLevel.bajo, RiskLevel.medio), RiskLevel.medio);
    expect(effectiveRiskLevel(RiskLevel.alto, RiskLevel.bajo), RiskLevel.alto);
    // Sólo una fuente presente → esa.
    expect(effectiveRiskLevel(RiskLevel.sinRiesgo, null), RiskLevel.sinRiesgo);
    expect(effectiveRiskLevel(null, RiskLevel.medio), RiskLevel.medio);
    // Ninguna → sin valoración.
    expect(effectiveRiskLevel(null, null), isNull);
  });
}
