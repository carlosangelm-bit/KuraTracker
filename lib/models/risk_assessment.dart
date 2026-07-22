/// Valoración de riesgo (Braden) independiente de una herida. Append-only; la
/// más reciente alimenta el motor de prevención (prevention_risk_engine.dart).
/// Ver migración 0036_prevention_module.sql.
class RiskAssessment {
  final String id;
  final String? organizationId;
  final String patientId;
  /// Escala de Braden (6-23). Menor = mayor riesgo de lesión por presión.
  final int? bradenScore;
  /// Subescalas opcionales (percepción, humedad, actividad, movilidad,
  /// nutrición, fricción) como objeto JSON.
  final Map<String, dynamic>? bradenSubscores;
  final DateTime assessedAt;
  final String? assessedBy; // staff.id
  final String? notes;
  final DateTime? createdAt;

  const RiskAssessment({
    required this.id,
    this.organizationId,
    required this.patientId,
    this.bradenScore,
    this.bradenSubscores,
    required this.assessedAt,
    this.assessedBy,
    this.notes,
    this.createdAt,
  });

  factory RiskAssessment.fromJson(Map<String, dynamic> json) => RiskAssessment(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String?,
        patientId: json['patient_id'] as String,
        bradenScore: (json['braden_score'] as num?)?.toInt(),
        bradenSubscores: (json['braden_subscores'] as Map?)?.cast<String, dynamic>(),
        assessedAt: DateTime.parse(json['assessed_at'] as String),
        assessedBy: json['assessed_by'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'patient_id': patientId,
        'braden_score': bradenScore,
        'braden_subscores': bradenSubscores,
        'assessed_at': assessedAt.toIso8601String(),
        'assessed_by': assessedBy,
        'notes': notes,
        'created_at': createdAt?.toIso8601String(),
      };
}
