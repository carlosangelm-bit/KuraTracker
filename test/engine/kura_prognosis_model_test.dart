// Tests de PARIDAD del modelo pronostico (seccion 8.1).
//
// Los valores esperados de este archivo fueron calculados de forma
// INDEPENDIENTE en Python siguiendo verbatim la especificacion (z-score,
// score lineal, softmax) y deben coincidir con la implementacion Dart con
// tolerancia de punto flotante (1e-9). Esto garantiza que la
// implementacion en el cliente Flutter reproduce exactamente la
// aritmetica especificada.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/kura_clinical_adjustments.dart';
import 'package:kuratracker/engine/kura_prognosis_model.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'clinical_params_fixture.dart';
import 'package:kuratracker/engine/models/kura_engine_input.dart';
import 'dart:io';

KuraPrognosisModel _loadModelFromFile() {
  final raw = File('assets/engine/kura_model_v2.json').readAsStringSync();
  return KuraPrognosisModel.fromJsonString(raw);
}

KuraClinicalAdjustments _loadAdjustmentsFromFile() {
  final raw =
      File('assets/engine/kura_clinical_adjustments.json').readAsStringSync();
  return KuraClinicalAdjustments.fromJsonString(raw);
}

KuraEngineInput _input({
  required Etiologia etiologia,
  required double area,
  required double necrosis,
  required double esfacelo,
  required double depth,
  required int nComorb,
  double? abi,
  double? alb,
}) {
  final comorb = <Comorbilidad, ComorbilidadEstado>{};
  final allComorb = Comorbilidad.values;
  for (var i = 0; i < nComorb && i < allComorb.length; i++) {
    comorb[allComorb[i]] = ComorbilidadEstado.presente;
  }
  return KuraEngineInput(
    etiologia: etiologia,
    entorno: Entorno.clinica,
    areaCm2: area,
    depthCm: depth,
    necrosisPct: necrosis,
    esfaceloPct: esfacelo,
    granulacionPct: 0,
    epitelizacionPct: 0,
    comorbilidades: comorb,
    abiPieDerecho: abi,
    abiPieIzquierdo: abi,
    esExtremidadInferior: abi != null,
    albuminaGdl: alb,
  );
}

void expectCloseMap(
  Map<String, double> actual,
  Map<String, double> expected, {
  double tol = 1e-9,
}) {
  for (final key in expected.keys) {
    expect(
      actual[key],
      closeTo(expected[key]!, tol),
      reason: 'Mismatch on key "$key"',
    );
  }
}

void main() {
  late KuraPrognosisModel model;
  late KuraClinicalAdjustments adjustments;

  setUpAll(() {
    loadClinicalParamsForTest();
    model = _loadModelFromFile();
    adjustments = _loadAdjustmentsFromFile();
  });

  group('Carga del modelo', () {
    test('carga correctamente todos los campos desde JSON', () {
      expect(model.modelVersion, 'kura_model_v2');
      expect(model.featureOrder, [
        'logarea',
        'necrosis_f',
        'esfacelo_f',
        'depth_f',
        'n_comorb_struct',
        'et_lpp',
        'et_vasc',
        'et_quir',
        'et_traum',
      ]);
      expect(model.intercept['A'], closeTo(0.06353920676509701, 1e-12));
      expect(model.coef['A']!['logarea'], closeTo(-0.15255089827670415, 1e-12));
    });
  });

  group('CASE 1: base, sin comorbilidades, sin etiologia especial, sin ABI/ALB', () {
    late KuraEngineInput input;
    setUp(() {
      input = _input(
        etiologia: Etiologia.otra,
        area: 10,
        necrosis: 20,
        esfacelo: 30,
        depth: 0.3,
        nComorb: 0,
      );
    });

    test('features calculados correctamente', () {
      final feat = model.computeFeatures(input);
      expect(feat['logarea'], closeTo(2.3978952727983707, 1e-9));
      expect(feat['necrosis_f'], 20);
      expect(feat['esfacelo_f'], 30);
      expect(feat['depth_f'], 0.3);
      expect(feat['n_comorb_struct'], 0);
      expect(feat['et_lpp'], 0);
      expect(feat['et_vasc'], 0);
      expect(feat['et_quir'], 0);
      expect(feat['et_traum'], 0);
    });

    test('z-scores y raw scores coinciden con referencia Python', () {
      final pipeline = model.computePipeline(input);
      expectCloseMap(pipeline.z, {
        'logarea': 0.979328159987931,
        'necrosis_f': 0.25515963965640476,
        'esfacelo_f': 0.3172569151491233,
        'depth_f': 0.01958514050057807,
        'n_comorb_struct': -0.7089534983068397,
        'et_lpp': -1.2033287165193058,
        'et_vasc': -0.19310136093052355,
        'et_quir': -0.285082592954487,
        'et_traum': -0.4259896494836248,
      }, tol: 1e-8);
      expectCloseMap(pipeline.rawScores, {
        'A': 0.23913399425244536,
        'B': -0.7586409855424354,
        'C': 0.5195069912899889,
      }, tol: 1e-8);
    });

    test('probabilidades finales (sin ajuste, categorias na) coinciden y suman 1', () {
      final pipeline = model.computePipeline(input);
      final adjustedScores = adjustments.applyAdjustments(
        rawScores: pipeline.rawScores,
        input: input,
      );
      // Sin ABI ni albumina, el ajuste debe ser 0 (categoria "na").
      expectCloseMap(adjustedScores, pipeline.rawScores, tol: 1e-12);

      final probs = KuraPrognosisModel.softmax(adjustedScores);
      expectCloseMap(probs, {
        'A': 0.3714265534756708,
        'B': 0.1369445586032814,
        'C': 0.49162888792104775,
      }, tol: 1e-8);
      final sum = probs.values.fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
    });
  });

  group('CASE 2: LPP, 2 comorb, ABI alto (0.9), ALB normal (3.8)', () {
    test('probabilidades coinciden con referencia Python', () {
      final input = _input(
        etiologia: Etiologia.lpp,
        area: 25,
        necrosis: 40,
        esfacelo: 10,
        depth: 1.0,
        nComorb: 2,
        abi: 0.9,
        alb: 3.8,
      );
      final pipeline = model.computePipeline(input);
      expectCloseMap(pipeline.rawScores, {
        'A': -0.42165602068556923,
        'B': -0.5758686519699017,
        'C': 0.9975246726554707,
      }, tol: 1e-8);

      final adjustedScores = adjustments.applyAdjustments(
        rawScores: pipeline.rawScores,
        input: input,
      );
      expectCloseMap(adjustedScores, {
        'A': 0.6783439793144308,
        'B': -0.2758686519699016,
        'C': -0.4024753273445293,
      }, tol: 1e-8);

      final probs = KuraPrognosisModel.softmax(adjustedScores);
      expectCloseMap(probs, {
        'A': 0.5799008702467393,
        'B': 0.22332867030801565,
        'C': 0.19677045944524502,
      }, tol: 1e-8);
    });
  });

  group('CASE 3: vascular, area=0, ABI critico (0.3 -> isquemia critica), ALB baja (2.5)', () {
    test('probabilidades coinciden con referencia Python (dominante C)', () {
      final input = _input(
        etiologia: Etiologia.vascular,
        area: 0,
        necrosis: 0,
        esfacelo: 0,
        depth: 0,
        nComorb: 1,
        abi: 0.3,
        alb: 2.5,
      );
      final pipeline = model.computePipeline(input);
      expectCloseMap(pipeline.rawScores, {
        'A': 0.9558386600076845,
        'B': -0.9151763719400824,
        'C': -0.04066228806760133,
      }, tol: 1e-8);

      final adjustedScores = adjustments.applyAdjustments(
        rawScores: pipeline.rawScores,
        input: input,
      );
      expectCloseMap(adjustedScores, {
        'A': -2.044161339992316,
        'B': -1.6151763719400825,
        'C': 3.5593377119323986,
      }, tol: 1e-8);

      final probs = KuraPrognosisModel.softmax(adjustedScores);
      expectCloseMap(probs, {
        'A': 0.0036508342314218916,
        'B': 0.0056065786438617244,
        'C': 0.9907425871247163,
      }, tol: 1e-8);

      expect(input.isquemiaCritica, isTrue);
    });
  });

  group('CASE 4: quirurgica, ABI moderado (0.65), ALB leve (3.2)', () {
    test('probabilidades coinciden con referencia Python', () {
      final input = _input(
        etiologia: Etiologia.quirurgica,
        area: 50,
        necrosis: 60,
        esfacelo: 20,
        depth: 2.0,
        nComorb: 3,
        abi: 0.65,
        alb: 3.2,
      );
      final pipeline = model.computePipeline(input);
      expectCloseMap(pipeline.rawScores, {
        'A': -0.4126882327832891,
        'B': -1.1091957323328216,
        'C': 1.521883965116115,
      }, tol: 1e-8);

      final adjustedScores = adjustments.applyAdjustments(
        rawScores: pipeline.rawScores,
        input: input,
      );
      expectCloseMap(adjustedScores, {
        'A': -1.0126882327832891,
        'B': 0.2908042676671784,
        'C': 1.2218839651161149,
      }, tol: 1e-8);

      final probs = KuraPrognosisModel.softmax(adjustedScores);
      expectCloseMap(probs, {
        'A': 0.07130318805757892,
        'B': 0.2625478996286879,
        'C': 0.6661489123137333,
      }, tol: 1e-8);
    });
  });

  group('CASE 5: traumatica, sin ABI/ALB', () {
    test('probabilidades coinciden con referencia Python', () {
      final input = _input(
        etiologia: Etiologia.traumatica,
        area: 5,
        necrosis: 5,
        esfacelo: 5,
        depth: 0.1,
        nComorb: 0,
      );
      final pipeline = model.computePipeline(input);
      expectCloseMap(pipeline.rawScores, {
        'A': -0.24618475015020816,
        'B': 0.14608101905012472,
        'C': 0.10010373110008047,
      }, tol: 1e-8);

      final probs = KuraPrognosisModel.softmax(pipeline.rawScores);
      expectCloseMap(probs, {
        'A': 0.2567960100875841,
        'B': 0.38014311637412296,
        'C': 0.3630608735382929,
      }, tol: 1e-8);
    });
  });

  group('Casos limite', () {
    test('area = 0 no produce NaN/Infinity (log(1+0)=0)', () {
      final input = _input(
        etiologia: Etiologia.otra,
        area: 0,
        necrosis: 0,
        esfacelo: 0,
        depth: 0,
        nComorb: 0,
      );
      final pipeline = model.computePipeline(input);
      expect(pipeline.features['logarea'], 0.0);
      expect(pipeline.rawScores.values.every((v) => v.isFinite), isTrue);
    });

    test('comorbilidades no evaluadas NO cuentan para n_comorb_struct', () {
      final comorb = <Comorbilidad, ComorbilidadEstado>{
        Comorbilidad.diabetesMellitus: ComorbilidadEstado.presente,
        Comorbilidad.obesidad: ComorbilidadEstado.noEvaluado,
        Comorbilidad.tabaquismoActivo: ComorbilidadEstado.negado,
        Comorbilidad.malnutricion: ComorbilidadEstado.presente,
      };
      final input = KuraEngineInput(
        etiologia: Etiologia.otra,
        entorno: Entorno.clinica,
        areaCm2: 5,
        depthCm: 0.2,
        necrosisPct: 10,
        esfaceloPct: 10,
        granulacionPct: 80,
        epitelizacionPct: 0,
        comorbilidades: comorb,
      );
      // Solo 2 estan "presente" (diabetesMellitus, malnutricion); las
      // noEvaluado y negado NO cuentan.
      expect(input.nComorbStruct, 2);
    });

    test('sin datos de ABI/albumina -> categoria na -> ajuste cero', () {
      final input = _input(
        etiologia: Etiologia.otra,
        area: 10,
        necrosis: 10,
        esfacelo: 10,
        depth: 0.2,
        nComorb: 0,
      );
      expect(input.abiCategory, AbiCategory.na);
      expect(input.albCategory, AlbCategory.na);
      final pipeline = model.computePipeline(input);
      final adjusted = adjustments.applyAdjustments(
        rawScores: pipeline.rawScores,
        input: input,
      );
      expectCloseMap(adjusted, pipeline.rawScores, tol: 1e-12);
    });

    test('herida NO de extremidad inferior ignora ABI aunque se capture', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.quirurgica,
        entorno: Entorno.clinica,
        areaCm2: 10,
        depthCm: 0.5,
        necrosisPct: 10,
        esfaceloPct: 10,
        granulacionPct: 80,
        epitelizacionPct: 0,
        comorbilidades: const {},
        abiPieDerecho: 0.2, // dato "capturado por error", no aplica
        esExtremidadInferior: false,
      );
      expect(input.abiCategory, AbiCategory.na);
      expect(input.isquemiaCritica, isFalse);
    });

    test('softmax es numericamente estable con scores extremos', () {
      final extremeScores = {'A': 1000.0, 'B': -1000.0, 'C': 0.0};
      final probs = KuraPrognosisModel.softmax(extremeScores);
      expect(probs.values.every((v) => v.isFinite), isTrue);
      expect(probs['A'], closeTo(1.0, 1e-9));
      final sum = probs.values.fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
    });
  });
}
