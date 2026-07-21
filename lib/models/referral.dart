/// Estado de una referencia/interconsulta.
enum ReferralStatus { enviada, respondida, cerrada }

extension ReferralStatusLabel on ReferralStatus {
  String get label {
    switch (this) {
      case ReferralStatus.enviada:
        return 'Enviada';
      case ReferralStatus.respondida:
        return 'Respondida';
      case ReferralStatus.cerrada:
        return 'Cerrada';
    }
  }

  String get dbValue => name;

  static ReferralStatus fromDb(String s) => ReferralStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => ReferralStatus.enviada,
      );
}

/// Adjuntos posibles de una referencia (checklist). Se persisten como objeto
/// JSON booleano en `referrals.adjuntos` (clave = [jsonKey]).
enum ReferralAdjunto { reporteEkare, resumenClinico, cultivo, itb, laboratorios }

extension ReferralAdjuntoLabel on ReferralAdjunto {
  String get jsonKey {
    switch (this) {
      case ReferralAdjunto.reporteEkare:
        return 'reporte_ekare';
      case ReferralAdjunto.resumenClinico:
        return 'resumen_clinico';
      case ReferralAdjunto.cultivo:
        return 'cultivo';
      case ReferralAdjunto.itb:
        return 'itb';
      case ReferralAdjunto.laboratorios:
        return 'laboratorios';
    }
  }

  String get label {
    switch (this) {
      case ReferralAdjunto.reporteEkare:
        return 'Reporte eKare';
      case ReferralAdjunto.resumenClinico:
        return 'Resumen clínico';
      case ReferralAdjunto.cultivo:
        return 'Cultivo';
      case ReferralAdjunto.itb:
        return 'ITB / Doppler';
      case ReferralAdjunto.laboratorios:
        return 'Laboratorios';
    }
  }

  static ReferralAdjunto? fromKey(String key) {
    for (final a in ReferralAdjunto.values) {
      if (a.jsonKey == key) return a;
    }
    return null;
  }
}

/// Especialidades sugeridas para la referencia (el campo admite texto libre).
const List<String> kReferralEspecialidades = [
  'Angiología / Cirugía vascular',
  'Infectología',
  'Cirugía',
  'Cirugía / Ortopedia',
  'Geriatría',
  'Endocrinología',
  'Dermatología',
  'Cirugía plástica',
  'Medicina interna',
  'Estomaterapia',
];

/// Referencia/interconsulta a un especialista (Prompt 6). Ver migración
/// 0029_referrals.sql.
class Referral {
  final String id;
  final String patientId;
  final String? woundId;
  final String? consultationId;
  final String? staffId;
  final String especialidad;
  final String motivo;
  final Set<ReferralAdjunto> adjuntos;
  final ReferralStatus status;
  final String? referralSignedBy;
  final String? referralSignedLicense;
  final String? returnDocRef;
  final String? returnNotes;
  final DateTime? returnedAt;
  final DateTime createdAt;

  const Referral({
    required this.id,
    required this.patientId,
    this.woundId,
    this.consultationId,
    this.staffId,
    required this.especialidad,
    required this.motivo,
    this.adjuntos = const {},
    this.status = ReferralStatus.enviada,
    this.referralSignedBy,
    this.referralSignedLicense,
    this.returnDocRef,
    this.returnNotes,
    this.returnedAt,
    required this.createdAt,
  });

  bool get isRespondida => returnedAt != null;

  factory Referral.fromJson(Map<String, dynamic> json) {
    final rawAdj = (json['adjuntos'] as Map?) ?? const {};
    final adj = <ReferralAdjunto>{};
    rawAdj.forEach((k, v) {
      if (v == true) {
        final a = ReferralAdjuntoLabel.fromKey(k as String);
        if (a != null) adj.add(a);
      }
    });
    return Referral(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      woundId: json['wound_id'] as String?,
      consultationId: json['consultation_id'] as String?,
      staffId: json['staff_id'] as String?,
      especialidad: json['especialidad'] as String,
      motivo: json['motivo'] as String,
      adjuntos: adj,
      status: ReferralStatusLabel.fromDb(json['status'] as String? ?? 'enviada'),
      referralSignedBy: json['referral_signed_by'] as String?,
      referralSignedLicense: json['referral_signed_license'] as String?,
      returnDocRef: json['return_doc_ref'] as String?,
      returnNotes: json['return_notes'] as String?,
      returnedAt: json['returned_at'] == null
          ? null
          : DateTime.parse(json['returned_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Checklist como objeto JSON booleano con TODAS las claves canónicas.
  Map<String, bool> adjuntosJson() => {
        for (final a in ReferralAdjunto.values) a.jsonKey: adjuntos.contains(a),
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'wound_id': woundId,
        'consultation_id': consultationId,
        'staff_id': staffId,
        'especialidad': especialidad,
        'motivo': motivo,
        'adjuntos': adjuntosJson(),
        'status': status.dbValue,
        'referral_signed_by': referralSignedBy,
        'referral_signed_license': referralSignedLicense,
        'return_doc_ref': returnDocRef,
        'return_notes': returnNotes,
        'returned_at': returnedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}
