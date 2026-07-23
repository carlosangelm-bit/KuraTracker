/// Estado de un internamiento hospitalario.
enum AdmissionStatus { activo, egresado }

extension AdmissionStatusX on AdmissionStatus {
  String get label {
    switch (this) {
      case AdmissionStatus.activo:
        return 'Internado';
      case AdmissionStatus.egresado:
        return 'Egresado';
    }
  }

  String get dbValue => name;

  static AdmissionStatus fromDb(String s) => AdmissionStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AdmissionStatus.activo,
      );
}

/// Internamiento hospitalario del paciente (unidad/cama/ingreso). Episódico:
/// una fila por internamiento; status=activo / discharged_at NULL = en curso.
/// Ver migración 0036_prevention_module.sql.
class PatientAdmission {
  final String id;
  final String? organizationId;
  final String patientId;
  final String? unit; // unidad / servicio (legacy/opcional)
  final String? floor; // piso
  final String? area; // área/servicio dentro del piso
  final String? bed; // cama
  final DateTime admittedAt;
  final DateTime? dischargedAt;
  final AdmissionStatus status;
  final String? notes;
  final DateTime? createdAt;

  const PatientAdmission({
    required this.id,
    this.organizationId,
    required this.patientId,
    this.unit,
    this.floor,
    this.area,
    this.bed,
    required this.admittedAt,
    this.dischargedAt,
    this.status = AdmissionStatus.activo,
    this.notes,
    this.createdAt,
  });

  /// Ubicación legible "Piso X · Área Y · Cama Z" (omite los vacíos).
  String get locationLabel {
    final parts = <String>[
      if ((floor ?? '').isNotEmpty) 'Piso $floor',
      if ((area ?? '').isNotEmpty) area!,
      if ((bed ?? '').isNotEmpty) 'Cama $bed',
    ];
    if (parts.isEmpty && (unit ?? '').isNotEmpty) return unit!;
    return parts.join(' · ');
  }

  bool get isActive => status == AdmissionStatus.activo;

  factory PatientAdmission.fromJson(Map<String, dynamic> json) =>
      PatientAdmission(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String?,
        patientId: json['patient_id'] as String,
        unit: json['unit'] as String?,
        floor: json['floor'] as String?,
        area: json['area'] as String?,
        bed: json['bed'] as String?,
        admittedAt: DateTime.parse(json['admitted_at'] as String),
        dischargedAt: json['discharged_at'] == null
            ? null
            : DateTime.parse(json['discharged_at'] as String),
        status: AdmissionStatusX.fromDb(json['status'] as String? ?? 'activo'),
        notes: json['notes'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'patient_id': patientId,
        'unit': unit,
        'floor': floor,
        'area': area,
        'bed': bed,
        'admitted_at': admittedAt.toIso8601String(),
        'discharged_at': dischargedAt?.toIso8601String(),
        'status': status.dbValue,
        'notes': notes,
        'created_at': createdAt?.toIso8601String(),
      };
}
