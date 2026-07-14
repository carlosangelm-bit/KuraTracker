// Tests de REGLAS DE SEGURIDAD y del motor de reglas de tratamiento (8.4).
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/engine/models/kura_engine_input.dart';
import 'package:kuratracker/engine/rules/kura_treatment_rules_engine.dart';

void main() {
  group('REGLA DE SEGURIDAD: no desbridar con isquemia critica (ABI<0.5)', () {
    test('ABI < 0.5 => NUNCA sugiere desbridamiento, siempre alerta + interconsulta urgente a angiologia', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.vascular,
        entorno: Entorno.clinica,
        areaCm2: 20,
        depthCm: 1.0,
        necrosisPct: 50, // composicion desbridable alta (>=15%)
        esfaceloPct: 30,
        granulacionPct: 20,
        epitelizacionPct: 0,
        comorbilidades: const {},
        abiPieDerecho: 0.35,
        abiPieIzquierdo: 0.42,
        esExtremidadInferior: true,
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.b,
      );

      final metodos = result.regimen.map((r) => r.metodo).toList();
      expect(metodos, isNot(contains('Desbridamiento')));

      expect(
        result.alertas.any((a) => a.contains('isquemia critica') || a.contains('NO se recomienda desbridamiento')),
        isTrue,
      );

      expect(
        result.interconsultas.any(
          (i) => i.especialidad.toLowerCase().contains('angiolog') && i.esUrgente,
        ),
        isTrue,
      );
    });

    test('ABI >= 0.5 con composicion desbridable alta SI sugiere desbridamiento', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.vascular,
        entorno: Entorno.clinica,
        areaCm2: 20,
        depthCm: 1.0,
        necrosisPct: 20,
        esfaceloPct: 20,
        granulacionPct: 60,
        epitelizacionPct: 0,
        comorbilidades: const {},
        abiPieDerecho: 0.85,
        abiPieIzquierdo: 0.9,
        esExtremidadInferior: true,
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      final metodos = result.regimen.map((r) => r.metodo).toList();
      expect(metodos, contains('Desbridamiento'));
    });

    test('composicion desbridable <15% NO sugiere desbridamiento aunque ABI sea normal', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.otra,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.2,
        necrosisPct: 5,
        esfaceloPct: 5, // total 10% < 15%
        granulacionPct: 90,
        epitelizacionPct: 0,
        comorbilidades: const {},
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      final metodos = result.regimen.map((r) => r.metodo).toList();
      expect(metodos, isNot(contains('Desbridamiento')));
    });
  });

  group('REGLA DE SEGURIDAD: WUWHS G4 -> interconsulta urgente', () {
    test('WUWHS G4 genera interconsulta urgente a cirugia y alerta', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.quirurgica,
        entorno: Entorno.clinica,
        areaCm2: 15,
        depthCm: 1.5,
        necrosisPct: 30,
        esfaceloPct: 20,
        granulacionPct: 50,
        epitelizacionPct: 0,
        comorbilidades: const {},
        wuwhsGrade: WuwhsGrade.g4,
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.b,
      );
      expect(
        result.interconsultas.any(
          (i) => i.especialidad.toLowerCase().contains('cirugia') && i.esUrgente,
        ),
        isTrue,
      );
      expect(
        result.alertas.any((a) => a.contains('URGENTE')),
        isTrue,
      );
    });

    test('WUWHS G1/G2 NO genera interconsulta urgente', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.quirurgica,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.3,
        necrosisPct: 5,
        esfaceloPct: 5,
        granulacionPct: 90,
        epitelizacionPct: 0,
        comorbilidades: const {},
        wuwhsGrade: WuwhsGrade.g1,
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(
        result.interconsultas.any((i) => i.esUrgente),
        isFalse,
      );
    });
  });

  group('Reglas generales de regimen', () {
    test('limpieza de la herida siempre esta presente', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.otra,
        entorno: Entorno.clinica,
        areaCm2: 1,
        depthCm: 0.1,
        necrosisPct: 0,
        esfaceloPct: 0,
        granulacionPct: 100,
        epitelizacionPct: 0,
        comorbilidades: const {},
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(result.regimen.map((r) => r.metodo), contains('Limpieza de la herida'));
    });

    test('profundidad >=0.5cm sugiere relleno de cavidad', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.otra,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.5,
        necrosisPct: 0,
        esfaceloPct: 0,
        granulacionPct: 100,
        epitelizacionPct: 0,
        comorbilidades: const {},
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(result.regimen.map((r) => r.metodo), contains('Relleno de cavidad'));
    });

    test('profundidad <0.5cm sin tunelizacion NO sugiere relleno', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.otra,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.2,
        necrosisPct: 0,
        esfaceloPct: 0,
        granulacionPct: 100,
        epitelizacionPct: 0,
        comorbilidades: const {},
        tunelizacionOSocavamiento: false,
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(result.regimen.map((r) => r.metodo), isNot(contains('Relleno de cavidad')));
    });

    test('exudado abundante sugiere aposito absorbente', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.otra,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.1,
        necrosisPct: 0,
        esfaceloPct: 0,
        granulacionPct: 100,
        epitelizacionPct: 0,
        comorbilidades: const {},
        exudadoCantidad: ExudadoCantidad.abundante,
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(result.regimen.map((r) => r.metodo), contains('Apósito'));
    });

    test('infeccion presente sugiere antimicrobiano topico', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.otra,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.1,
        necrosisPct: 0,
        esfaceloPct: 0,
        granulacionPct: 100,
        epitelizacionPct: 0,
        comorbilidades: const {},
        infeccionCriterios: {InfeccionCriterioIwii.exudadoPurulento},
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(
        result.regimen.map((r) => r.metodo),
        contains('Tratamiento para la infección'),
      );
    });

    test('entorno domicilio siempre incluye educacion al cuidador', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.otra,
        entorno: Entorno.domicilio,
        areaCm2: 10,
        depthCm: 0.1,
        necrosisPct: 0,
        esfaceloPct: 0,
        granulacionPct: 100,
        epitelizacionPct: 0,
        comorbilidades: const {},
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(
        result.regimen.map((r) => r.metodo),
        contains('Educación al paciente/cuidador'),
      );
    });

    test('ulcera venosa con ABI critico NO sugiere compresion (contraindicada)', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.vascular,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.1,
        necrosisPct: 0,
        esfaceloPct: 0,
        granulacionPct: 100,
        epitelizacionPct: 0,
        comorbilidades: const {},
        abiPieDerecho: 0.3,
        abiPieIzquierdo: 0.3,
        esExtremidadInferior: true,
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.c,
      );
      expect(
        result.regimen.map((r) => r.metodo),
        isNot(contains('Terapia compresiva')),
      );
      expect(
        result.alertas.any((a) => a.contains('CONTRAINDICADA')),
        isTrue,
      );
    });

    test('pie diabetico Wagner G4 genera interconsulta urgente a cirugia/ortopedia', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.pieDiabetico,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 1.0,
        necrosisPct: 20,
        esfaceloPct: 10,
        granulacionPct: 70,
        epitelizacionPct: 0,
        comorbilidades: const {},
        wagnerGrade: WagnerGrade.g4,
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.c,
      );
      expect(
        result.interconsultas.any((i) => i.esUrgente),
        isTrue,
      );
    });

    test('herida por arma de fuego siempre genera interconsulta urgente a cirugia de trauma', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.traumatica,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 1.0,
        necrosisPct: 10,
        esfaceloPct: 10,
        granulacionPct: 80,
        epitelizacionPct: 0,
        comorbilidades: const {},
        agenteCausal: AgenteCausal.armaFuego,
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.b,
      );
      expect(
        result.interconsultas.any(
          (i) => i.especialidad.toLowerCase().contains('trauma') && i.esUrgente,
        ),
        isTrue,
      );
    });

    test('necrosis extensa (>=30%) genera interconsulta a cirugia', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.otra,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.5,
        necrosisPct: 35,
        esfaceloPct: 0,
        granulacionPct: 65,
        epitelizacionPct: 0,
        comorbilidades: const {},
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.b,
      );
      expect(
        result.interconsultas.any((i) => i.especialidad == 'Cirugia'),
        isTrue,
      );
    });
  });
}
