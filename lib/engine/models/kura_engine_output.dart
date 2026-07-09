import 'kura_engine_enums.dart';

/// Un componente sugerido del regimen de tratamiento (metodo + producto).
class RegimenComponente {
  final String metodo; // p.ej. "Desbridamiento"
  final String producto; // p.ej. "Autolitico"
  final String justificacion;
  final bool esAlerta; // true si es una alerta de seguridad (p.ej. no desbridar)

  const RegimenComponente({
    required this.metodo,
    required this.producto,
    required this.justificacion,
    this.esAlerta = false,
  });

  Map<String, dynamic> toJson() => {
        'metodo': metodo,
        'producto': producto,
        'justificacion': justificacion,
        'es_alerta': esAlerta,
      };

  factory RegimenComponente.fromJson(Map<String, dynamic> json) => RegimenComponente(
        metodo: json['metodo'] as String,
        producto: json['producto'] as String,
        justificacion: json['justificacion'] as String,
        esAlerta: json['es_alerta'] as bool? ?? false,
      );
}

/// Una interconsulta sugerida automaticamente por el motor de reglas.
class Interconsulta {
  final String especialidad;
  final String motivo;
  final bool esUrgente;

  const Interconsulta({
    required this.especialidad,
    required this.motivo,
    this.esUrgente = false,
  });

  Map<String, dynamic> toJson() => {
        'especialidad': especialidad,
        'motivo': motivo,
        'es_urgente': esUrgente,
      };

  factory Interconsulta.fromJson(Map<String, dynamic> json) => Interconsulta(
        especialidad: json['especialidad'] as String,
        motivo: json['motivo'] as String,
        esUrgente: json['es_urgente'] as bool? ?? false,
      );
}

/// Salida completa del motor "Protocolo Kura+" para una valoracion dada.
/// Se persiste integramente junto a la consulta para trazabilidad
/// (version del modelo, timestamp, y si el clinico acepto/edito).
class KuraEngineOutput {
  final String modelVersion; // p.ej. "kura_model_v2"
  final String adjustmentsVersion; // p.ej. "kura_adjustments_v1"
  final String rulesVersion; // p.ej. "kura_rules_v1"
  final DateTime generatedAt;

  /// Probabilidades finales (tras softmax + ajustes), suman ~1.0.
  final Map<KuraScenario, double> probabilities;

  /// Escenario con mayor probabilidad.
  final KuraScenario dominantScenario;

  final List<RegimenComponente> regimen;
  final List<Interconsulta> interconsultas;
  final List<String> alertas;

  /// Features estandarizados usados (para depuracion/auditoria).
  final Map<String, double> debugFeatures;
  final Map<String, double> debugRawScores;

  const KuraEngineOutput({
    required this.modelVersion,
    required this.adjustmentsVersion,
    required this.rulesVersion,
    required this.generatedAt,
    required this.probabilities,
    required this.dominantScenario,
    required this.regimen,
    required this.interconsultas,
    required this.alertas,
    this.debugFeatures = const {},
    this.debugRawScores = const {},
  });

  Map<String, dynamic> toJson() => {
        'model_version': modelVersion,
        'adjustments_version': adjustmentsVersion,
        'rules_version': rulesVersion,
        'generated_at': generatedAt.toIso8601String(),
        'probabilities': probabilities.map((k, v) => MapEntry(k.code, v)),
        'dominant_scenario': dominantScenario.code,
        'regimen': regimen.map((r) => r.toJson()).toList(),
        'interconsultas': interconsultas.map((i) => i.toJson()).toList(),
        'alertas': alertas,
        'debug_features': debugFeatures,
        'debug_raw_scores': debugRawScores,
      };

  factory KuraEngineOutput.fromJson(Map<String, dynamic> json) {
    KuraScenario _scn(String code) =>
        KuraScenario.values.firstWhere((e) => e.code == code);
    final probsRaw = (json['probabilities'] as Map).cast<String, dynamic>();
    return KuraEngineOutput(
      modelVersion: json['model_version'] as String,
      adjustmentsVersion: json['adjustments_version'] as String,
      rulesVersion: json['rules_version'] as String,
      generatedAt: DateTime.parse(json['generated_at'] as String),
      probabilities: probsRaw.map((k, v) => MapEntry(_scn(k), (v as num).toDouble())),
      dominantScenario: _scn(json['dominant_scenario'] as String),
      regimen: ((json['regimen'] as List?) ?? [])
          .map((r) => RegimenComponente.fromJson(r as Map<String, dynamic>))
          .toList(),
      interconsultas: ((json['interconsultas'] as List?) ?? [])
          .map((i) => Interconsulta.fromJson(i as Map<String, dynamic>))
          .toList(),
      alertas: ((json['alertas'] as List?) ?? []).cast<String>(),
      debugFeatures: ((json['debug_features'] as Map?) ?? {})
          .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      debugRawScores: ((json['debug_raw_scores'] as Map?) ?? {})
          .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
    );
  }
}

/// Registro de la decision del clinico sobre la recomendacion del motor,
/// requerido para trazabilidad/validacion prospectiva (seccion 9).
enum ClinicianDecision { pendiente, aceptada, editada, rechazada }
