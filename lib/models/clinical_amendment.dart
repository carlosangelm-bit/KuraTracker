/// Nota de enmienda / aclaración a una nota clínica (NOM-004, Fase 4).
/// Append-only e inmutable: corrige sin sobrescribir el original. Ver
/// migración 0033_clinical_amendments.sql.
class ClinicalAmendment {
  final String id;
  final String patientId;
  final String? consultationId;
  final String body;
  final String? reason;
  final String? staffId;
  final String? signedBy;
  final String? signedLicense;
  final DateTime createdAt;

  const ClinicalAmendment({
    required this.id,
    required this.patientId,
    this.consultationId,
    required this.body,
    this.reason,
    this.staffId,
    this.signedBy,
    this.signedLicense,
    required this.createdAt,
  });

  factory ClinicalAmendment.fromJson(Map<String, dynamic> json) =>
      ClinicalAmendment(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        consultationId: json['consultation_id'] as String?,
        body: json['body'] as String,
        reason: json['reason'] as String?,
        staffId: json['staff_id'] as String?,
        signedBy: json['signed_by'] as String?,
        signedLicense: json['signed_license'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'consultation_id': consultationId,
        'body': body,
        'reason': reason,
        'staff_id': staffId,
        'signed_by': signedBy,
        'signed_license': signedLicense,
        'created_at': createdAt.toIso8601String(),
      };
}
