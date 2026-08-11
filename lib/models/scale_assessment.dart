/// Valoración de una escala clínica puntuable/repetible (GLOBIAD, PUSH, RESVECH,
/// ISTAP, STAR, extravasación, ASEPSIS, …). Append-only; la más reciente por
/// `scaleId` alimenta el motor de prevención. Ver migración 0084_scale_assessments.sql.
///
/// `subscores` = respuestas por ítem; `totalScore` para métodos SUMA;
/// `categoryResult` para CATEGÓRICO (p. ej. GLOBIAD "2A"); `bandId` la banda.
class ScaleAssessment {
  final String id;
  final String? organizationId;
  final String patientId;
  final String? woundId;
  final String scaleId;
  final String? scaleVersion;
  final Map<String, dynamic>? subscores;
  final double? totalScore;
  final String? categoryResult;
  final String? bandId;
  final DateTime assessedAt;
  final String? assessedBy; // staff.id
  final String? notes;
  final DateTime? createdAt;

  const ScaleAssessment({
    required this.id,
    this.organizationId,
    required this.patientId,
    this.woundId,
    required this.scaleId,
    this.scaleVersion,
    this.subscores,
    this.totalScore,
    this.categoryResult,
    this.bandId,
    required this.assessedAt,
    this.assessedBy,
    this.notes,
    this.createdAt,
  });

  factory ScaleAssessment.fromJson(Map<String, dynamic> json) => ScaleAssessment(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String?,
        patientId: json['patient_id'] as String,
        woundId: json['wound_id'] as String?,
        scaleId: json['scale_id'] as String,
        scaleVersion: json['scale_version'] as String?,
        subscores: (json['subscores'] as Map?)?.cast<String, dynamic>(),
        totalScore: (json['total_score'] as num?)?.toDouble(),
        categoryResult: json['category_result'] as String?,
        bandId: json['band_id'] as String?,
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
        'wound_id': woundId,
        'scale_id': scaleId,
        'scale_version': scaleVersion,
        'subscores': subscores,
        'total_score': totalScore,
        'category_result': categoryResult,
        'band_id': bandId,
        'assessed_at': assessedAt.toIso8601String(),
        'assessed_by': assessedBy,
        'notes': notes,
        'created_at': createdAt?.toIso8601String(),
      };
}
