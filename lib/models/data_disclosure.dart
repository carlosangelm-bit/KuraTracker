/// Un registro de divulgación: una salida de datos clínicos de la plataforma
/// (CSV de mediciones/consultas, expediente de un paciente, entrega del centro).
/// Distinto de audit_log (cambios). Ver migración 0101. Inmutable en la BD.
class DataDisclosure {
  final String id;
  final String organizationId;
  final String? actorId;
  final String? actorEmail;
  final String kind; // csv_mediciones | csv_consultas | expediente_paciente | entrega_centro
  final Map<String, dynamic>? scope;
  final int? recordCount;
  final int? patientCount;
  final int? photoCount;
  final int? missingCount;
  final String? fileName;
  final DateTime occurredAt;

  const DataDisclosure({
    required this.id,
    required this.organizationId,
    this.actorId,
    this.actorEmail,
    required this.kind,
    this.scope,
    this.recordCount,
    this.patientCount,
    this.photoCount,
    this.missingCount,
    this.fileName,
    required this.occurredAt,
  });

  /// Etiqueta legible del tipo de divulgación.
  String get kindLabel {
    switch (kind) {
      case 'csv_mediciones':
        return 'CSV de mediciones';
      case 'csv_consultas':
        return 'CSV de consultas';
      case 'expediente_paciente':
        return 'Expediente de un paciente';
      case 'entrega_centro':
        return 'Entrega completa del centro';
      default:
        return kind;
    }
  }

  factory DataDisclosure.fromJson(Map<String, dynamic> j) => DataDisclosure(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        actorId: j['actor_id'] as String?,
        actorEmail: j['actor_email'] as String?,
        kind: j['kind'] as String,
        scope: (j['scope'] as Map?)?.cast<String, dynamic>(),
        recordCount: (j['record_count'] as num?)?.toInt(),
        patientCount: (j['patient_count'] as num?)?.toInt(),
        photoCount: (j['photo_count'] as num?)?.toInt(),
        missingCount: (j['missing_count'] as num?)?.toInt(),
        fileName: j['file_name'] as String?,
        occurredAt: DateTime.parse(j['occurred_at'] as String),
      );
}
