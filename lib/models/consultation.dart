enum VisitType { valoracion, seguimiento, interconsulta, egreso }

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
      };
}
