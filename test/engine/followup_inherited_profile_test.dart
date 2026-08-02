// fix/followup-inherited-profile — el seguimiento HEREDA el perfil diagnóstico
// de la herida (subtipo vascular, no revascularizable, Braden) en vez de
// perderlo. Estos golden fijan que, para el mismo estado clínico, valoración y
// seguimiento producen el mismo régimen, y cubren los casos clínicos clave.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/engine/models/kura_engine_input.dart';
import 'package:kuratracker/engine/models/kura_engine_output.dart';
import 'package:kuratracker/engine/rules/kura_treatment_rules_engine.dart';
import 'package:kuratracker/models/wound.dart';

import 'clinical_params_fixture.dart';

Wound _wound({
  required Etiologia etiology,
  SubtipoVascular? subtipoVascular,
  bool noRevascularizable = false,
}) =>
    Wound(
      id: 'w1',
      patientId: 'p1',
      etiology: etiology,
      bodyLocationPrimary: 'pierna',
      subtipoVascular: subtipoVascular,
      noRevascularizable: noRevascularizable,
      createdAt: DateTime(2024, 1, 1),
    );

/// Construye el input igual que ambos flujos: subtipo/no-revascularizable desde
/// la herida persistida, y el Braden desde el PERFIL del paciente
/// (latestRiskAssessment, no de la visita). Modela la construcción de
/// KuraEngineInput de follow_up_capture_screen tras el fix.
KuraEngineInput _inputFromWound(
  Wound wound, {
  required double abi,
  int? braden, // en la app viene de repo.latestRiskAssessment(patientId)
}) =>
    KuraEngineInput(
      etiologia: wound.etiology,
      entorno: Entorno.clinica,
      areaCm2: 10,
      depthCm: 0.3,
      necrosisPct: 0,
      esfaceloPct: 0,
      granulacionPct: 80,
      epitelizacionPct: 20,
      comorbilidades: const {},
      abiPieDerecho: abi,
      abiPieIzquierdo: abi,
      esExtremidadInferior: true,
      exudadoCantidad: ExudadoCantidad.escaso,
      wagnerGrade: wound.wagnerGrade,
      ceapClass: wound.ceapClass,
      wuwhsGrade: wound.wuwhsGrade,
      agenteCausal: wound.agenteCausal,
      subtipoVascular: wound.subtipoVascular,
      noRevascularizable: wound.noRevascularizable,
      bradenScore: braden,
    );

List<String> _regimenKey(
        ({
          List<String> alertas,
          List<Interconsulta> interconsultas,
          List<RegimenComponente> regimen
        }) r) =>
    r.regimen.map((c) => '${c.metodo}|${c.producto}').toList();

void main() {
  setUpAll(loadClinicalParamsForTest);

  test('el perfil vascular round-trips por toJson/fromJson (persistencia 0072)',
      () {
    final w = _wound(
      etiology: Etiologia.vascular,
      subtipoVascular: SubtipoVascular.arterial,
      noRevascularizable: true,
    );
    final back = Wound.fromJson(w.toJson());
    expect(back.subtipoVascular, SubtipoVascular.arterial);
    expect(back.noRevascularizable, isTrue);
  });

  test(
      'CONSISTENCIA: valoración y seguimiento dan el MISMO régimen para el mismo '
      'estado (arterial, ABI 0.7)', () {
    final wound = _wound(
      etiology: Etiologia.vascular,
      subtipoVascular: SubtipoVascular.arterial,
    );
    // Valoración: el motor recibe el subtipo directo del formulario.
    final valoracion = _inputFromWound(wound, abi: 0.7);
    // Seguimiento: hereda el mismo subtipo desde la herida persistida (incluso
    // tras un round-trip de BD).
    final seguimiento = _inputFromWound(Wound.fromJson(wound.toJson()), abi: 0.7);

    final rV = KuraTreatmentRulesEngine.generate(
        input: valoracion, scenario: KuraScenario.b);
    final rS = KuraTreatmentRulesEngine.generate(
        input: seguimiento, scenario: KuraScenario.b);
    expect(_regimenKey(rS), _regimenKey(rV));
  });

  test(
      'OBLIGATORIO: úlcera vascular arterial (ABI 0.7) en seguimiento → Terapia '
      'seca, sin compresión ni cura húmeda', () {
    final wound = _wound(
      etiology: Etiologia.vascular,
      subtipoVascular: SubtipoVascular.arterial,
    );
    final r = KuraTreatmentRulesEngine.generate(
      input: _inputFromWound(wound, abi: 0.7),
      scenario: KuraScenario.b,
    );
    final metodos = r.regimen.map((c) => c.metodo).toList();
    expect(metodos, contains('Terapia seca'));
    expect(metodos, isNot(contains('Terapia compresiva')));
    // 'Limpieza de la herida' = cura húmeda por defecto, suprimida en terapia seca.
    expect(metodos, isNot(contains('Limpieza de la herida')));
  });

  test(
      'REGRESIÓN: sin heredar el subtipo (bug viejo) la MISMA herida NO recibe '
      'terapia seca', () {
    // subtipoVascular == null reproduce el estado previo al fix.
    final wound = _wound(etiology: Etiologia.vascular, subtipoVascular: null);
    final r = KuraTreatmentRulesEngine.generate(
      input: _inputFromWound(wound, abi: 0.7),
      scenario: KuraScenario.b,
    );
    final metodos = r.regimen.map((c) => c.metodo).toList();
    expect(metodos, isNot(contains('Terapia seca')));
    expect(metodos, contains('Limpieza de la herida'));
  });

  test('LPP con Braden heredado en seguimiento incluye la modalidad de tratamiento',
      () {
    final wound = _wound(etiology: Etiologia.lpp);
    // Braden 14 (riesgo medio) → a cargo de la clínica.
    final r = KuraTreatmentRulesEngine.generate(
      input: _inputFromWound(wound, abi: 1.0, braden: 14),
      scenario: KuraScenario.b,
    );
    final modalidad = r.regimen
        .where((c) => c.metodo == 'Modalidad de tratamiento (LPP)')
        .toList();
    expect(modalidad, isNotEmpty);
    expect(modalidad.first.producto, contains('clínica'));
  });

  test('LPP SIN Braden heredado (bug viejo) NO incluye la modalidad', () {
    final wound = _wound(etiology: Etiologia.lpp);
    final r = KuraTreatmentRulesEngine.generate(
      input: _inputFromWound(wound, abi: 1.0, braden: null),
      scenario: KuraScenario.b,
    );
    expect(r.regimen.map((c) => c.metodo),
        isNot(contains('Modalidad de tratamiento (LPP)')));
  });
}
