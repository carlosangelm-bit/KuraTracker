// GOLDEN SAFETY NET — motor de reglas de tratamiento (8.4), Fase A.
//
// Captura la salida ACTUAL del motor (regimen, interconsultas, alertas) para
// una batería representativa de inputs y la fija en test/engine/golden_cases.json.
// Estos golden deben seguir pasando IDÉNTICOS tras el refactor data-driven
// (garantiza cero cambio de conducta clínica). Es un refactor puro.
//
// Si el archivo golden NO existe, se genera (y el test lo reporta). Si existe,
// se VERIFICA caso por caso. Para regenerar a propósito (tras un cambio de
// conducta APROBADO por María), borrar el .json y correr de nuevo.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/engine/models/kura_engine_input.dart';
import 'package:kuratracker/engine/models/kura_engine_output.dart';
import 'package:kuratracker/engine/rules/kura_treatment_rules_engine.dart';

const _goldenPath = 'test/engine/golden_cases.json';

/// Input base (herida benigna) con overrides por caso.
KuraEngineInput _in({
  Etiologia etiologia = Etiologia.otra,
  Entorno entorno = Entorno.clinica,
  double area = 10,
  double depth = 0.3,
  double necrosis = 0,
  double esfacelo = 0,
  double granulacion = 80,
  double epitelizacion = 20,
  Map<Comorbilidad, ComorbilidadEstado> comorbilidades = const {},
  double? abiDer,
  double? abiIzq,
  bool esExtremidadInferior = false,
  double? albumina,
  bool tunelizacion = false,
  ExudadoCantidad exudado = ExudadoCantidad.escaso,
  Set<PielPerilesionalEstado> piel = const {},
  Set<InfeccionCriterioIwii> infeccion = const {},
  bool cuidador = false,
  bool fragil = false,
  WagnerGrade? wagner,
  WuwhsGrade? wuwhs,
  AgenteCausal? agente,
  SubtipoVascular? subtipoVascular,
  bool noRevascularizable = false,
  int? braden,
  bool lppRecurrente = false,
  bool cuidadosPaliativos = false,
  bool dolorCronico = false,
  double? tunnelDepth,
  bool sobreArticulacion = false,
}) =>
    KuraEngineInput(
      etiologia: etiologia,
      entorno: entorno,
      areaCm2: area,
      depthCm: depth,
      necrosisPct: necrosis,
      esfaceloPct: esfacelo,
      granulacionPct: granulacion,
      epitelizacionPct: epitelizacion,
      comorbilidades: comorbilidades,
      abiPieDerecho: abiDer,
      abiPieIzquierdo: abiIzq,
      esExtremidadInferior: esExtremidadInferior,
      albuminaGdl: albumina,
      tunelizacionOSocavamiento: tunelizacion,
      exudadoCantidad: exudado,
      pielPerilesional: piel,
      infeccionCriterios: infeccion,
      tieneCuidadorIdentificado: cuidador,
      pacienteFragil: fragil,
      wagnerGrade: wagner,
      wuwhsGrade: wuwhs,
      agenteCausal: agente,
      subtipoVascular: subtipoVascular,
      noRevascularizable: noRevascularizable,
      bradenScore: braden,
      lppRecurrente: lppRecurrente,
      cuidadosPaliativos: cuidadosPaliativos,
      dolorCronico: dolorCronico,
      tunnelDepthCm: tunnelDepth,
      sobreArticulacion: sobreArticulacion,
    );

class _Case {
  final String name;
  final KuraEngineInput input;
  final KuraScenario scenario;
  const _Case(this.name, this.input, this.scenario);
}

/// Batería representativa: etiologías, bandas de ITB/ABI, Wagner 0–5, WUWHS 1–4,
/// necrosis 15/30%, infección (local/propagada/sistémica), LPP por Braden,
/// túnel/articulación, traumáticas, exudado/piel, geriatría, escenario C.
List<_Case> _cases() => [
      // ---- Vascular: bandas de compresión por ITB ----
      _Case('venosa_abi_1.0_compresion_fuerte',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.venosa, esExtremidadInferior: true, abiDer: 1.0, abiIzq: 1.05, exudado: ExudadoCantidad.moderado), KuraScenario.b),
      _Case('venosa_abi_0.85_precaucion',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.venosa, esExtremidadInferior: true, abiDer: 0.85, abiIzq: 0.9), KuraScenario.b),
      _Case('venosa_abi_0.7_reducida',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.venosa, esExtremidadInferior: true, abiDer: 0.7, abiIzq: 0.75), KuraScenario.b),
      _Case('venosa_abi_0.55_noaplica',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.venosa, esExtremidadInferior: true, abiDer: 0.55, abiIzq: 0.58), KuraScenario.b),
      _Case('venosa_itb_1.5_incompresible',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.venosa, esExtremidadInferior: true, abiDer: 1.5, abiIzq: 1.5), KuraScenario.b),
      _Case('venosa_sin_itb',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.venosa, esExtremidadInferior: true), KuraScenario.b),
      // ---- Arterial / isquémica (terapia seca) ----
      _Case('arterial_abi_0.85_terapia_seca',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.arterial, esExtremidadInferior: true, abiDer: 0.85, abiIzq: 0.9, necrosis: 20), KuraScenario.b),
      _Case('arterial_no_revascularizable',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.venosa, esExtremidadInferior: true, abiDer: 0.9, abiIzq: 0.95, noRevascularizable: true), KuraScenario.b),
      _Case('isquemia_critica_abi_0.35',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.arterial, esExtremidadInferior: true, abiDer: 0.35, abiIzq: 0.42, necrosis: 40, esfacelo: 20), KuraScenario.b),
      // ---- Desbridamiento / necrosis ----
      _Case('necrosis_15_desbridamiento_clinica',
          _in(necrosis: 15, granulacion: 65), KuraScenario.b),
      _Case('necrosis_15_desbridamiento_domicilio',
          _in(entorno: Entorno.domicilio, necrosis: 15, granulacion: 65), KuraScenario.b),
      _Case('necrosis_30_extensa',
          _in(necrosis: 30, granulacion: 50), KuraScenario.b),
      _Case('composicion_10_no_desbrida',
          _in(necrosis: 5, esfacelo: 5, granulacion: 70), KuraScenario.b),
      // ---- Relleno / apósito / piel ----
      _Case('profundidad_0.6_relleno',
          _in(depth: 0.6), KuraScenario.b),
      _Case('tunelizacion_relleno',
          _in(tunelizacion: true), KuraScenario.b),
      _Case('exudado_abundante_aposito',
          _in(exudado: ExudadoCantidad.abundante), KuraScenario.b),
      _Case('piel_seca_fragil_proteccion',
          _in(piel: {PielPerilesionalEstado.seca, PielPerilesionalEstado.fragil}), KuraScenario.b),
      // ---- Infección escalonada ----
      _Case('infeccion_local_2_factores',
          _in(infeccion: {InfeccionCriterioIwii.exudadoPurulento, InfeccionCriterioIwii.calorLocal}), KuraScenario.b),
      _Case('infeccion_propagada_eritema',
          _in(infeccion: {InfeccionCriterioIwii.eritemaMayor2cm}), KuraScenario.b),
      _Case('infeccion_sistemica_celulitis',
          _in(etiologia: Etiologia.vascular, subtipoVascular: SubtipoVascular.venosa, esExtremidadInferior: true, abiDer: 1.0, abiIzq: 1.0, infeccion: {InfeccionCriterioIwii.celulitis, InfeccionCriterioIwii.fiebre}), KuraScenario.b),
      // ---- Pie diabético: Wagner 0–5 ----
      for (final w in WagnerGrade.values)
        _Case('pie_diabetico_wagner_${w.name}',
            _in(etiologia: Etiologia.pieDiabetico, wagner: w, necrosis: 10), KuraScenario.b),
      // ---- Quirúrgica: WUWHS 1–4 ----
      for (final g in WuwhsGrade.values)
        _Case('quirurgica_wuwhs_${g.name}',
            _in(etiologia: Etiologia.quirurgica, wuwhs: g), KuraScenario.b),
      // ---- Traumática: agentes ----
      for (final a in AgenteCausal.values)
        _Case('traumatica_${a.name}',
            _in(etiologia: Etiologia.traumatica, agente: a), KuraScenario.b),
      // ---- LPP: modalidad por Braden ----
      _Case('lpp_braden_9_muy_alto', _in(etiologia: Etiologia.lpp, braden: 9), KuraScenario.b),
      _Case('lpp_braden_11_alto', _in(etiologia: Etiologia.lpp, braden: 11), KuraScenario.b),
      _Case('lpp_braden_15_medio', _in(etiologia: Etiologia.lpp, braden: 15), KuraScenario.b),
      _Case('lpp_braden_20_bajo', _in(etiologia: Etiologia.lpp, braden: 20), KuraScenario.b),
      _Case('lpp_sin_braden', _in(etiologia: Etiologia.lpp), KuraScenario.b),
      _Case('lpp_recurrente_geriatria', _in(etiologia: Etiologia.lpp, braden: 10, lppRecurrente: true), KuraScenario.b),
      // ---- Referencias por túnel / articulación ----
      _Case('tunel_8cm_referencia', _in(tunnelDepth: 8), KuraScenario.b),
      _Case('tunel_5cm_sin_referencia', _in(tunnelDepth: 5), KuraScenario.b),
      _Case('articulacion_referencia', _in(sobreArticulacion: true), KuraScenario.b),
      // ---- Geriatría / educación / escenario ----
      _Case('paciente_fragil_geriatria', _in(fragil: true), KuraScenario.b),
      _Case('cuidados_paliativos_geriatria', _in(cuidadosPaliativos: true), KuraScenario.b),
      _Case('dolor_cronico_geriatria', _in(dolorCronico: true), KuraScenario.b),
      _Case('domicilio_cuidador_educacion', _in(entorno: Entorno.domicilio, cuidador: true), KuraScenario.b),
      _Case('escenario_c_contencion', _in(), KuraScenario.c),
      _Case('escenario_a_baseline', _in(), KuraScenario.a),
    ];

Map<String, dynamic> _outToJson(
    ({List<RegimenComponente> regimen, List<Interconsulta> interconsultas, List<String> alertas}) r) =>
    {
      'regimen': r.regimen
          .map((c) => {'metodo': c.metodo, 'producto': c.producto, 'justificacion': c.justificacion})
          .toList(),
      'interconsultas': r.interconsultas
          .map((i) => {'especialidad': i.especialidad, 'motivo': i.motivo, 'esUrgente': i.esUrgente})
          .toList(),
      'alertas': r.alertas,
    };

void main() {
  final cases = _cases();
  final file = File(_goldenPath);

  test('los nombres de los casos golden son únicos', () {
    final names = cases.map((c) => c.name).toList();
    expect(names.toSet().length, names.length, reason: 'Hay nombres duplicados en la batería golden.');
  });

  if (!file.existsSync()) {
    test('GENERAR golden_cases.json (no existía)', () {
      final out = [
        for (final c in cases)
          {
            'name': c.name,
            'scenario': c.scenario.name,
            'input': c.input.toJson(),
            'expected': _outToJson(
              KuraTreatmentRulesEngine.generate(input: c.input, scenario: c.scenario),
            ),
          }
      ];
      file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
      // ignore: avoid_print
      print('Golden generado: ${cases.length} casos en $_goldenPath. '
          'Revísalo y vuelve a correr para que se VERIFIQUE.');
    });
    return;
  }

  group('GOLDEN: la salida del motor no cambia (refactor puro)', () {
    final stored = (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final byName = {for (final c in cases) c.name: c};

    test('el golden cubre exactamente la batería (sin casos huérfanos ni faltantes)', () {
      final storedNames = stored.map((e) => e['name'] as String).toSet();
      expect(storedNames, byName.keys.toSet(),
          reason: 'La batería y el golden difieren en el set de casos. '
              'Si agregaste/quitaste casos, borra $_goldenPath y regenera.');
    });

    for (final entry in stored) {
      final name = entry['name'] as String;
      test(name, () {
        final c = byName[name];
        expect(c, isNotNull, reason: 'Caso golden "$name" ya no existe en la batería.');
        final result = KuraTreatmentRulesEngine.generate(
          input: c!.input,
          scenario: c.scenario,
        );
        expect(_outToJson(result), entry['expected'],
            reason: 'La salida del motor para "$name" cambió respecto al golden. '
                'Si NO fue un cambio de conducta aprobado, es una REGRESIÓN.');
      });
    }
  });
}
