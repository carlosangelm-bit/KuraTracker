import 'kura_clinical_adjustments.dart';
import 'kura_prognosis_model.dart';
import 'models/kura_engine_enums.dart';
import 'models/kura_engine_input.dart';
import 'models/kura_engine_output.dart';
import 'rules/kura_treatment_rules_engine.dart';

/// Orquestador principal del motor "Protocolo Kura+" (seccion 8 completa).
///
/// Este es el UNICO punto de entrada que debe usar la UI para obtener una
/// recomendacion del motor. Encapsula:
///   1. Modelo pronostico multinomial (8.1)
///   2. Ajustes clinicos por ABI/albumina (8.2)
///   3. Softmax final -> probabilidades por escenario (8.3)
///   4. Motor de reglas de tratamiento determinístico (8.4)
///
/// El resultado se etiqueta siempre con la version del modelo/reglas
/// usada, para trazabilidad (seccion 9). Esta misma logica se replica en
/// la Edge Function de Supabase (supabase/functions/kura-protocol-engine)
/// para que el calculo pueda ejecutarse tanto en cliente (pronostico en
/// vivo mientras se captura) como en backend (persistencia autoritativa).
class KuraProtocolEngine {
  final KuraPrognosisModel model;
  final KuraClinicalAdjustments adjustments;

  const KuraProtocolEngine({
    required this.model,
    required this.adjustments,
  });

  static KuraProtocolEngine? _cached;

  /// Carga (y cachea) el motor completo desde los assets empaquetados.
  static Future<KuraProtocolEngine> load() async {
    if (_cached != null) return _cached!;
    final model = await KuraPrognosisModel.loadFromAssets();
    final adjustments = await KuraClinicalAdjustments.loadFromAssets();
    final engine = KuraProtocolEngine(model: model, adjustments: adjustments);
    _cached = engine;
    return engine;
  }

  /// Ejecuta el pipeline completo y produce la recomendacion final.
  KuraEngineOutput run(KuraEngineInput input) {
    final pipeline = model.computePipeline(input);
    final adjustedScores = adjustments.applyAdjustments(
      rawScores: pipeline.rawScores,
      input: input,
    );
    final probsRaw = KuraPrognosisModel.softmax(adjustedScores);

    final probabilities = <KuraScenario, double>{
      KuraScenario.a: probsRaw['A'] ?? 0.0,
      KuraScenario.b: probsRaw['B'] ?? 0.0,
      KuraScenario.c: probsRaw['C'] ?? 0.0,
    };

    final dominant = probabilities.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    final rulesResult = KuraTreatmentRulesEngine.generate(
      input: input,
      scenario: dominant,
    );

    return KuraEngineOutput(
      modelVersion: model.modelVersion,
      adjustmentsVersion: adjustments.adjustmentsVersion,
      rulesVersion: KuraTreatmentRulesEngine.rulesVersion,
      generatedAt: DateTime.now().toUtc(),
      probabilities: probabilities,
      dominantScenario: dominant,
      regimen: rulesResult.regimen,
      interconsultas: rulesResult.interconsultas,
      alertas: rulesResult.alertas,
      debugFeatures: pipeline.features,
      debugRawScores: pipeline.rawScores,
    );
  }
}
