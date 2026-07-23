/// Vínculo cuidador↔paciente. Ver 0042_preventive_tasks.sql. El centro autoriza
/// a un usuario cuidador a monitorear (solo lectura) a pacientes concretos.
class CaregiverPatientAssignment {
  final String id;
  final String organizationId;
  final String caregiverProfileId;
  final String patientId;
  final String? assignedBy;
  final DateTime createdAt;

  const CaregiverPatientAssignment({
    required this.id,
    required this.organizationId,
    required this.caregiverProfileId,
    required this.patientId,
    this.assignedBy,
    required this.createdAt,
  });

  factory CaregiverPatientAssignment.fromJson(Map<String, dynamic> json) =>
      CaregiverPatientAssignment(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String,
        caregiverProfileId: json['caregiver_profile_id'] as String,
        patientId: json['patient_id'] as String,
        assignedBy: json['assigned_by'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'caregiver_profile_id': caregiverProfileId,
        'patient_id': patientId,
        'assigned_by': assignedBy,
        'created_at': createdAt.toIso8601String(),
      };
}
