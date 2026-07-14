enum VisitType { valoracion, seguimiento, interconsulta, egreso, cierre }

extension VisitTypeLabel on VisitType {
  String get label {
    switch (this) {
      case VisitType.valoracion:
        return 'Valoracion';
      case VisitType.seguimiento:
        return 'Seguimiento';
      case VisitType.interconsulta:
        return 'Interconsulta';
      case VisitType.egreso:
        return 'Egreso';
      case VisitType.cierre:
        return 'Cierre';
    }
  }

  /// Numero de fotos exigido por el Protocolo de Fotografias §1.2 segun el
  /// tipo de visita: valoracion inicial = 3 (antes/despues de limpiar +
  /// con medicion), seguimiento = 2 (despues de limpiar sin medicion + con
  /// medicion), cierre = 1 (herida cicatrizada, sin medicion, para el
  /// reporte final). interconsulta/egreso no tienen un requisito fijo de
  /// fotografia en el protocolo, se dejan en 0 (opcional).
  int get requiredPhotoCount {
    switch (this) {
      case VisitType.valoracion:
        return 3;
      case VisitType.seguimiento:
        return 2;
      case VisitType.cierre:
        return 1;
      case VisitType.interconsulta:
      case VisitType.egreso:
        return 0;
    }
  }

  String get dbValue => name;

  static VisitType fromDb(String s) =>
      VisitType.values.firstWhere((e) => e.name == s, orElse: () => VisitType.valoracion);
}

class Consultation {
  final String id;
  final String patientId;
  final String staffId;
  final String siteId;
  final VisitType visitType;
  final DateTime visitDate;
  final Map<String, dynamic>? vitalSigns;
  final bool isDraft;
  final DateTime createdAt;
  // Nota de seguimiento obligatoria (Instructivo de Archivo). Aplica a
  // visit_type=seguimiento; sin campos vacios segun protocolo.
  final String? followUpCareType;
  final String? followUpProcedureDesc;
  final String? followUpMaterialsUsed;
  final String? followUpEvolution;
  final String? followUpSignedBy;
  final String? followUpSignedLicense;

  const Consultation({
    required this.id,
    required this.patientId,
    required this.staffId,
    required this.siteId,
    required this.visitType,
    required this.visitDate,
    this.vitalSigns,
    this.isDraft = false,
    required this.createdAt,
    this.followUpCareType,
    this.followUpProcedureDesc,
    this.followUpMaterialsUsed,
    this.followUpEvolution,
    this.followUpSignedBy,
    this.followUpSignedLicense,
  });

  factory Consultation.fromJson(Map<String, dynamic> json) => Consultation(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        staffId: json['staff_id'] as String,
        siteId: json['site_id'] as String,
        visitType: VisitTypeLabel.fromDb(json['visit_type'] as String),
        visitDate: DateTime.parse(json['visit_date'] as String),
        vitalSigns: json['vital_signs'] as Map<String, dynamic>?,
        isDraft: json['is_draft'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        followUpCareType: json['follow_up_care_type'] as String?,
        followUpProcedureDesc: json['follow_up_procedure_desc'] as String?,
        followUpMaterialsUsed: json['follow_up_materials_used'] as String?,
        followUpEvolution: json['follow_up_evolution'] as String?,
        followUpSignedBy: json['follow_up_signed_by'] as String?,
        followUpSignedLicense: json['follow_up_signed_license'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'staff_id': staffId,
        'site_id': siteId,
        'visit_type': visitType.dbValue,
        'visit_date': visitDate.toIso8601String().substring(0, 10),
        'vital_signs': vitalSigns,
        'is_draft': isDraft,
        'created_at': createdAt.toIso8601String(),
        'follow_up_care_type': followUpCareType,
        'follow_up_procedure_desc': followUpProcedureDesc,
        'follow_up_materials_used': followUpMaterialsUsed,
        'follow_up_evolution': followUpEvolution,
        'follow_up_signed_by': followUpSignedBy,
        'follow_up_signed_license': followUpSignedLicense,
      };
}
