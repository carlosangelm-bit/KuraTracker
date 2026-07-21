// Tests de REGLAS DE SEGURIDAD y del motor de reglas de tratamiento (8.4).
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/engine/models/kura_engine_input.dart';
import 'package:kuratracker/engine/models/kura_engine_output.dart';
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

    test(
        'kura_rules_v2: sospecha de infeccion local (>=2 factores locales) '
        'sugiere antimicrobiano topico', () {
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
        infeccionCriterios: {
          InfeccionCriterioIwii.exudadoPurulento,
          InfeccionCriterioIwii.calorLocal,
        },
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(
        result.regimen.map((r) => r.metodo),
        contains('Tratamiento para la infección'),
      );
      expect(
        result.regimen
            .firstWhere((r) => r.metodo == 'Tratamiento para la infección')
            .producto,
        contains('PHMB'),
      );
      // La propagacion NO esta presente: no debe generarse interconsulta
      // urgente por infeccion propagada.
      expect(
        result.interconsultas.any(
          (i) => i.especialidad.toLowerCase().contains('infectolog') && i.esUrgente,
        ),
        isFalse,
      );
    });

    test(
        'kura_rules_v2: 1 solo factor local NO alcanza para sospecha de '
        'infeccion (sin antimicrobiano)', () {
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
        isNot(contains('Tratamiento para la infección')),
      );
    });

    test(
        'kura_rules_v2: solo aumento de exudado (exudadoAumentado) NO cuenta '
        'como factor local valido (sin antimicrobiano)', () {
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
        // exudadoAumentado + otro criterio ajeno a los 7 factores locales
        // (retrasoDeCicatrizacion no cuenta como factor local significativo).
        infeccionCriterios: {
          InfeccionCriterioIwii.exudadoAumentado,
          InfeccionCriterioIwii.retrasoDeCicatrizacion,
        },
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(
        result.regimen.map((r) => r.metodo),
        isNot(contains('Tratamiento para la infección')),
      );
    });

    test(
        'kura_rules_v2: infeccion propagada (eritema >2cm) genera '
        'interconsulta urgente + tratamiento sistemico, SIN antimicrobiano '
        'topico', () {
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
        infeccionCriterios: {InfeccionCriterioIwii.eritemaMayor2cm},
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      final componentesInfeccion = result.regimen
          .where((r) => r.metodo == 'Tratamiento para la infección')
          .toList();
      expect(componentesInfeccion, hasLength(1));
      expect(componentesInfeccion.first.producto, isNot(contains('PHMB')));
      expect(componentesInfeccion.first.producto, isNot(contains('plata')));
      expect(
        result.interconsultas.any(
          (i) => i.especialidad.toLowerCase().contains('infectolog') && i.esUrgente,
        ),
        isTrue,
      );
    });

    test(
        'kura_rules_v2: propagacion via celulitis/fiebre/malestar general '
        'tambien excluye el antimicrobiano topico', () {
      for (final criterio in [
        InfeccionCriterioIwii.celulitis,
        InfeccionCriterioIwii.fiebre,
        InfeccionCriterioIwii.malestarGeneral,
      ]) {
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
          infeccionCriterios: {criterio},
        );
        final result = KuraTreatmentRulesEngine.generate(
          input: input,
          scenario: KuraScenario.a,
        );
        final componentesInfeccion = result.regimen
            .where((r) => r.metodo == 'Tratamiento para la infección')
            .toList();
        expect(componentesInfeccion, hasLength(1), reason: 'criterio=$criterio');
        expect(componentesInfeccion.first.producto, isNot(contains('PHMB')),
            reason: 'criterio=$criterio');
        expect(
          result.interconsultas.any((i) => i.esUrgente),
          isTrue,
          reason: 'criterio=$criterio',
        );
      }
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

    test(
        'ulcera venosa con sospecha de infeccion LOCAL (>=2 factores) '
        'CONTINUA la compresion con vigilancia', () {
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
        abiPieDerecho: 0.85,
        abiPieIzquierdo: 0.9,
        esExtremidadInferior: true,
        infeccionCriterios: const {
          InfeccionCriterioIwii.exudadoPurulento,
          InfeccionCriterioIwii.calorLocal,
        },
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.c,
      );
      expect(
        result.regimen.map((r) => r.metodo),
        contains('Terapia compresiva'),
      );
      expect(
        result.alertas.any((a) => a.contains('CONTINUA')),
        isTrue,
      );
      expect(
        result.alertas.any((a) => a.contains('SUSPENDIDA')),
        isFalse,
      );
    });

    test(
        'ulcera venosa con eritema >2cm AISLADO (sin celulitis/fiebre/malestar) '
        'CONTINUA la compresion con vigilancia', () {
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
        abiPieDerecho: 0.85,
        abiPieIzquierdo: 0.9,
        esExtremidadInferior: true,
        infeccionCriterios: const {
          InfeccionCriterioIwii.eritemaMayor2cm,
        },
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.c,
      );
      expect(
        result.regimen.map((r) => r.metodo),
        contains('Terapia compresiva'),
      );
      expect(
        result.alertas.any((a) => a.contains('CONTINUA')),
        isTrue,
      );
      expect(
        result.alertas.any((a) => a.contains('SUSPENDIDA')),
        isFalse,
      );
    });

    for (final criterio in [
      InfeccionCriterioIwii.celulitis,
      InfeccionCriterioIwii.fiebre,
      InfeccionCriterioIwii.malestarGeneral,
    ]) {
      test(
          'ulcera venosa con infeccion SISTEMICA (${criterio.name}) '
          'SUSPENDE la compresion', () {
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
          abiPieDerecho: 0.85,
          abiPieIzquierdo: 0.9,
          esExtremidadInferior: true,
          infeccionCriterios: {criterio},
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
          result.alertas.any((a) => a.contains('SUSPENDIDA')),
          isTrue,
        );
      });
    }

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

  // ===========================================================================
  // TERAPIA SECA: úlcera arterial / isquémica / no revascularizable.
  // Protocolos: "Terapia seca", "Úlceras MMII", "Interconsultas".
  // ===========================================================================
  group('Úlcera ARTERIAL / terapia seca', () {
    KuraEngineInput arterial({
      double? abiDer,
      double? abiIzq,
      SubtipoVascular subtipo = SubtipoVascular.arterial,
      bool noRevascularizable = false,
      double necrosisPct = 40,
      double esfaceloPct = 10,
      double granulacionPct = 50,
    }) {
      return KuraEngineInput(
        etiologia: Etiologia.vascular,
        entorno: Entorno.clinica,
        areaCm2: 12,
        depthCm: 0.2,
        necrosisPct: necrosisPct,
        esfaceloPct: esfaceloPct,
        granulacionPct: granulacionPct,
        epitelizacionPct: 0,
        comorbilidades: const {},
        abiPieDerecho: abiDer,
        abiPieIzquierdo: abiIzq,
        esExtremidadInferior: true,
        subtipoVascular: subtipo,
        noRevascularizable: noRevascularizable,
      );
    }

    test(
        'CASO CLAVE: úlcera arterial ABI 0.85 -> terapia seca; SIN compresión '
        'ni desbridamiento cortante', () {
      final result = KuraTreatmentRulesEngine.generate(
        input: arterial(abiDer: 0.85, abiIzq: 0.9),
        scenario: KuraScenario.b,
      );
      final metodos = result.regimen.map((r) => r.metodo).toList();

      // Terapia seca presente; limpieza húmeda por defecto suprimida.
      expect(metodos, contains('Terapia seca'));
      expect(metodos, isNot(contains('Limpieza de la herida')));
      expect(
        result.regimen
            .firstWhere((r) => r.metodo == 'Terapia seca')
            .producto,
        allOf(contains('Yodopovidona'), contains('escara')),
      );

      // Sin compresión y sin desbridamiento (aunque necrosis+esfacelo=50%).
      expect(metodos, isNot(contains('Terapia compresiva')));
      expect(metodos, isNot(contains('Desbridamiento')));

      // Alerta de desbridamiento cortante contraindicado.
      expect(
        result.alertas.any((a) =>
            a.contains('CORTANTE CONTRAINDICADO') ||
            a.contains('Terapia seca')),
        isTrue,
      );

      // Derivación a angiología (ITB 0.85 < 0.9).
      expect(
        result.interconsultas.any(
            (i) => i.especialidad.toLowerCase().contains('angiolog')),
        isTrue,
      );
    });

    test('úlcera arterial NO agrega relleno de cavidad ni apósito absorbente',
        () {
      final input = KuraEngineInput(
        etiologia: Etiologia.vascular,
        entorno: Entorno.clinica,
        areaCm2: 12,
        depthCm: 1.2, // >=0.5 normalmente gatilla relleno
        necrosisPct: 40,
        esfaceloPct: 5,
        granulacionPct: 55,
        epitelizacionPct: 0,
        comorbilidades: const {},
        abiPieDerecho: 0.85,
        abiPieIzquierdo: 0.9,
        esExtremidadInferior: true,
        subtipoVascular: SubtipoVascular.arterial,
        exudadoCantidad: ExudadoCantidad.abundante, // normalmente gatilla apósito
      );
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.b,
      );
      final metodos = result.regimen.map((r) => r.metodo).toList();
      expect(metodos, isNot(contains('Relleno de cavidad')));
      expect(metodos, isNot(contains('Apósito')));
    });

    test(
        'no revascularizable (ITB normal) -> terapia seca aunque no haya '
        'isquemia crítica', () {
      final result = KuraTreatmentRulesEngine.generate(
        input: arterial(
          abiDer: 1.0,
          abiIzq: 1.0,
          subtipo: SubtipoVascular.venosa,
          noRevascularizable: true,
        ),
        scenario: KuraScenario.b,
      );
      final metodos = result.regimen.map((r) => r.metodo).toList();
      expect(metodos, contains('Terapia seca'));
      expect(metodos, isNot(contains('Terapia compresiva')));
    });
  });

  group('Recalibración ABI/ITB — techo superior y compresión (MMII)', () {
    KuraEngineInput venosa({required double abi, double necrosisPct = 0}) {
      return KuraEngineInput(
        etiologia: Etiologia.vascular,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.1,
        necrosisPct: necrosisPct,
        esfaceloPct: 0,
        granulacionPct: 100 - necrosisPct,
        epitelizacionPct: 0,
        comorbilidades: const {},
        abiPieDerecho: abi,
        abiPieIzquierdo: abi,
        esExtremidadInferior: true,
        subtipoVascular: SubtipoVascular.venosa,
      );
    }

    test('CASO CLAVE: ITB 1.5 -> NO comprimir + derivar angiología', () {
      final result = KuraTreatmentRulesEngine.generate(
        input: venosa(abi: 1.5),
        scenario: KuraScenario.a,
      );
      expect(
        result.regimen.map((r) => r.metodo),
        isNot(contains('Terapia compresiva')),
      );
      expect(
        result.alertas.any((a) => a.contains('ITB > 1.4')),
        isTrue,
      );
      expect(
        result.interconsultas.any(
            (i) => i.especialidad.toLowerCase().contains('angiolog')),
        isTrue,
      );
    });

    test('ITB 1.5 -> abiCategory.incompresible (techo superior)', () {
      expect(venosa(abi: 1.5).abiCategory, AbiCategory.incompresible);
      expect(venosa(abi: 1.5).itbCompresionBand,
          ItbCompresionBand.incompresible);
    });

    test('CASO CLAVE: venosa ITB 1.0 -> compresión fuerte SÍ', () {
      final result = KuraTreatmentRulesEngine.generate(
        input: venosa(abi: 1.0),
        scenario: KuraScenario.a,
      );
      final comp = result.regimen
          .where((r) => r.metodo == 'Terapia compresiva')
          .toList();
      expect(comp, hasLength(1));
      expect(comp.first.producto, contains('fuerte'));
    });

    test('venosa ITB 0.85 -> compresión con precaución + derivar angiología',
        () {
      final result = KuraTreatmentRulesEngine.generate(
        input: venosa(abi: 0.85),
        scenario: KuraScenario.a,
      );
      final comp = result.regimen
          .where((r) => r.metodo == 'Terapia compresiva')
          .toList();
      expect(comp, hasLength(1));
      expect(comp.first.producto.toLowerCase(), contains('precauci'));
      expect(
        result.interconsultas.any(
            (i) => i.especialidad.toLowerCase().contains('angiolog')),
        isTrue,
      );
    });

    test('venosa ITB 0.7 -> compresión reducida (máx 20 mmHg) + derivar', () {
      final result = KuraTreatmentRulesEngine.generate(
        input: venosa(abi: 0.7),
        scenario: KuraScenario.a,
      );
      final comp = result.regimen
          .where((r) => r.metodo == 'Terapia compresiva')
          .toList();
      expect(comp, hasLength(1));
      expect(comp.first.producto, contains('20 mmHg'));
      expect(
        result.interconsultas.any(
            (i) => i.especialidad.toLowerCase().contains('angiolog')),
        isTrue,
      );
    });

    test('venosa ITB 0.55 (<0.6, no crítico) -> NO comprimir + derivar', () {
      final input = venosa(abi: 0.55);
      // 0.55 no es isquemia crítica (>=0.5) pero sí fuera de rango de compresión.
      expect(input.isquemiaCritica, isFalse);
      final result = KuraTreatmentRulesEngine.generate(
        input: input,
        scenario: KuraScenario.a,
      );
      expect(
        result.regimen.map((r) => r.metodo),
        isNot(contains('Terapia compresiva')),
      );
      expect(
        result.alertas.any((a) => a.contains('ITB < 0.6')),
        isTrue,
      );
    });

    test('bandas ITB del protocolo MMII se mapean correctamente', () {
      expect(venosa(abi: 1.45).itbCompresionBand,
          ItbCompresionBand.incompresible);
      expect(venosa(abi: 1.2).itbCompresionBand, ItbCompresionBand.fuerte);
      expect(venosa(abi: 0.9).itbCompresionBand, ItbCompresionBand.fuerte);
      expect(
          venosa(abi: 0.85).itbCompresionBand, ItbCompresionBand.precaucion);
      expect(venosa(abi: 0.8).itbCompresionBand, ItbCompresionBand.precaucion);
      expect(venosa(abi: 0.7).itbCompresionBand, ItbCompresionBand.reducida);
      expect(venosa(abi: 0.6).itbCompresionBand, ItbCompresionBand.reducida);
      expect(venosa(abi: 0.5).itbCompresionBand, ItbCompresionBand.noAplica);
    });
  });

  // ===========================================================================
  // PROMPT 4 — Ajustes al motor de reglas (interconsultas, Braden, túnel/art.)
  // Protocolos "Interconsultas", etiologías.
  // ===========================================================================
  KuraEngineInput base({
    Etiologia etiologia = Etiologia.otra,
    int? bradenScore,
    bool lppRecurrente = false,
    bool cuidadosPaliativos = false,
    bool dolorCronico = false,
    bool pacienteFragil = false,
    double? tunnelDepthCm,
    bool sobreArticulacion = false,
    double? abiDer,
    double? abiIzq,
    bool esExtremidadInferior = false,
    SubtipoVascular? subtipoVascular,
  }) {
    return KuraEngineInput(
      etiologia: etiologia,
      entorno: Entorno.clinica,
      areaCm2: 10,
      depthCm: 0.2,
      necrosisPct: 0,
      esfaceloPct: 0,
      granulacionPct: 100,
      epitelizacionPct: 0,
      comorbilidades: const {},
      bradenScore: bradenScore,
      lppRecurrente: lppRecurrente,
      cuidadosPaliativos: cuidadosPaliativos,
      dolorCronico: dolorCronico,
      pacienteFragil: pacienteFragil,
      tunnelDepthCm: tunnelDepthCm,
      sobreArticulacion: sobreArticulacion,
      abiPieDerecho: abiDer,
      abiPieIzquierdo: abiIzq,
      esExtremidadInferior: esExtremidadInferior,
      subtipoVascular: subtipoVascular,
    );
  }

  bool hasEspecialidad(dynamic result, String needle) =>
      (result.interconsultas as List<Interconsulta>).any((i) =>
          i.especialidad.toLowerCase().contains(needle.toLowerCase()));

  int countAngiologia(dynamic result) =>
      (result.interconsultas as List<Interconsulta>)
          .where((i) => i.especialidad.toLowerCase().contains('angiolog'))
          .length;

  group('Interconsulta a GERIATRIA (Protocolo Interconsultas)', () {
    test('LPP recurrente genera geriatría', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(etiologia: Etiologia.lpp, lppRecurrente: true),
        scenario: KuraScenario.b,
      );
      expect(hasEspecialidad(r, 'geriatr'), isTrue);
      expect(
        r.interconsultas
            .firstWhere((i) => i.especialidad == 'Geriatria')
            .motivo,
        contains('LPP recurrente'),
      );
    });

    test('cuidados paliativos genera geriatría', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(cuidadosPaliativos: true),
        scenario: KuraScenario.c,
      );
      expect(hasEspecialidad(r, 'geriatr'), isTrue);
    });

    test('dolor crónico genera geriatría', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(dolorCronico: true),
        scenario: KuraScenario.b,
      );
      expect(hasEspecialidad(r, 'geriatr'), isTrue);
    });

    test('LPP NO recurrente sin otros factores NO genera geriatría', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(etiologia: Etiologia.lpp, bradenScore: 15),
        scenario: KuraScenario.a,
      );
      expect(hasEspecialidad(r, 'geriatr'), isFalse);
    });
  });

  group('Interconsulta a ANGIOLOGIA por ITB (coordinada con fix arterial)', () {
    test('pie diabético (no vascular) con ITB 0.85 genera angiología', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(
          etiologia: Etiologia.pieDiabetico,
          esExtremidadInferior: true,
          abiDer: 0.85,
          abiIzq: 0.9,
        ),
        scenario: KuraScenario.b,
      );
      expect(hasEspecialidad(r, 'angiolog'), isTrue);
    });

    test('ITB normal (1.0) NO genera angiología', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(
          etiologia: Etiologia.pieDiabetico,
          esExtremidadInferior: true,
          abiDer: 1.0,
          abiIzq: 1.05,
        ),
        scenario: KuraScenario.a,
      );
      expect(hasEspecialidad(r, 'angiolog'), isFalse);
    });

    test('venosa con ITB 0.85: EXACTAMENTE una angiología (sin duplicar)', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(
          etiologia: Etiologia.vascular,
          subtipoVascular: SubtipoVascular.venosa,
          esExtremidadInferior: true,
          abiDer: 0.85,
          abiIzq: 0.9,
        ),
        scenario: KuraScenario.b,
      );
      expect(countAngiologia(r), 1);
    });

    test('arterial con ITB 0.85: EXACTAMENTE una angiología (sin duplicar)', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(
          etiologia: Etiologia.vascular,
          subtipoVascular: SubtipoVascular.arterial,
          esExtremidadInferior: true,
          abiDer: 0.85,
          abiIzq: 0.9,
        ),
        scenario: KuraScenario.b,
      );
      expect(countAngiologia(r), 1);
    });

    test('ITB 1.5 (>1.4) genera angiología', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(
          etiologia: Etiologia.otra,
          esExtremidadInferior: true,
          abiDer: 1.5,
          abiIzq: 1.5,
        ),
        scenario: KuraScenario.a,
      );
      expect(hasEspecialidad(r, 'angiolog'), isTrue);
    });
  });

  group('Braden -> modalidad de tratamiento en LPP', () {
    RegimenComponente? modalidad(dynamic r) {
      final m = r.regimen
          .where((c) => c.metodo == 'Modalidad de tratamiento (LPP)')
          .toList();
      return m.isEmpty ? null : m.first as RegimenComponente;
    }

    test('Braden <=12 (riesgo alto) -> a cargo de la clínica', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(etiologia: Etiologia.lpp, bradenScore: 11),
        scenario: KuraScenario.b,
      );
      final comp = modalidad(r);
      expect(comp, isNotNull);
      expect(comp!.producto.toLowerCase(), contains('clínica'));
    });

    test('Braden >=13 (riesgo moderado/bajo) -> tratamiento compartido', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(etiologia: Etiologia.lpp, bradenScore: 16),
        scenario: KuraScenario.b,
      );
      final comp = modalidad(r);
      expect(comp, isNotNull);
      expect(comp!.producto.toLowerCase(), contains('compartido'));
    });

    test('sin Braden no se agrega la modalidad', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(etiologia: Etiologia.lpp),
        scenario: KuraScenario.b,
      );
      expect(modalidad(r), isNull);
    });

    test('modalidad de LPP no aplica a otras etiologías', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(etiologia: Etiologia.otra, bradenScore: 10),
        scenario: KuraScenario.b,
      );
      expect(modalidad(r), isNull);
    });
  });

  group('Referencia por túnel > 7 cm o articulación', () {
    test('túnel 8 cm genera referencia a cirugía', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(tunnelDepthCm: 8),
        scenario: KuraScenario.b,
      );
      expect(
        r.interconsultas.any((i) =>
            i.especialidad.toLowerCase().contains('cirugia') &&
            i.motivo.toLowerCase().contains('túnel')),
        isTrue,
      );
    });

    test('túnel 5 cm NO genera referencia por túnel', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(tunnelDepthCm: 5),
        scenario: KuraScenario.b,
      );
      expect(
        r.interconsultas.any((i) => i.motivo.toLowerCase().contains('túnel')),
        isFalse,
      );
    });

    test('compromiso articular genera referencia a cirugía/ortopedia', () {
      final r = KuraTreatmentRulesEngine.generate(
        input: base(sobreArticulacion: true),
        scenario: KuraScenario.b,
      );
      expect(
        r.interconsultas.any((i) =>
            i.especialidad.toLowerCase().contains('ortopedia') &&
            i.motivo.toLowerCase().contains('articular')),
        isTrue,
      );
    });
  });
}
