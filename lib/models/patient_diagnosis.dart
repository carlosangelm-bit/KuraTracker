import '../engine/cie10_catalog.dart';

/// Estado del ciclo de vida de un diagnóstico en el expediente.
/// Modelo append-only (igual que las comorbilidades): no se borra, un dx que
/// deja de aplicar se marca `resuelto` o `descartado`.
enum DiagnosisStatus { activo, resuelto, descartado }

extension DiagnosisStatusX on DiagnosisStatus {
  String get label {
    switch (this) {
      case DiagnosisStatus.activo:
        return 'Activo';
      case DiagnosisStatus.resuelto:
        return 'Resuelto';
      case DiagnosisStatus.descartado:
        return 'Descartado';
    }
  }

  String get dbValue => name;

  static DiagnosisStatus fromDb(String s) => DiagnosisStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => DiagnosisStatus.activo,
      );
}

/// Un diagnóstico CIE-10 asignado a un paciente (NOM-004). Referencia un
/// código del catálogo (asset) y guarda un SNAPSHOT del nombre para que el
/// registro sea inmutable aunque el catálogo cambie. Alcance documental: no
/// alimenta el motor Kura+. Ver migración 0034_patient_diagnoses.sql.
class PatientDiagnosis {
  final String id;
  final String? organizationId;
  final String patientId;
  final String? woundId;
  final String? staffId;
  final String code;
  final String name;
  final DiagnosisRelation relation;
  final bool isPrimary;
  final DiagnosisStatus status;
  final String? notes;
  // Atribución fecha + autor exigida por la NOM-004 (migración 0034).
  final DateTime? notedAt;
  final String? notedBy; // staff.id que registró/actualizó
  final DateTime? createdAt;

  const PatientDiagnosis({
    required this.id,
    this.organizationId,
    required this.patientId,
    this.woundId,
    this.staffId,
    required this.code,
    required this.name,
    required this.relation,
    this.isPrimary = false,
    this.status = DiagnosisStatus.activo,
    this.notes,
    this.notedAt,
    this.notedBy,
    this.createdAt,
  });

  factory PatientDiagnosis.fromJson(Map<String, dynamic> json) =>
      PatientDiagnosis(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String?,
        patientId: json['patient_id'] as String,
        woundId: json['wound_id'] as String?,
        staffId: json['staff_id'] as String?,
        code: json['code'] as String,
        name: json['name'] as String,
        relation: DiagnosisRelationX.fromDb(json['relation'] as String),
        isPrimary: json['is_primary'] as bool? ?? false,
        status: DiagnosisStatusX.fromDb(json['status'] as String? ?? 'activo'),
        notes: json['notes'] as String?,
        notedAt: json['noted_at'] == null
            ? null
            : DateTime.parse(json['noted_at'] as String),
        notedBy: json['noted_by'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'patient_id': patientId,
        'wound_id': woundId,
        'staff_id': staffId,
        'code': code,
        'name': name,
        'relation': relation.dbValue,
        'is_primary': isPrimary,
        'status': status.dbValue,
        'notes': notes,
        'noted_at': notedAt?.toIso8601String(),
        'noted_by': notedBy,
        'created_at': createdAt?.toIso8601String(),
      };
}
