/// Tipo de consentimiento informado del paciente (Protocolos "Expedientes
/// clínicos" y "Desbridamiento").
enum ConsentType { privacidad, fotografia, desbridamiento }

extension ConsentTypeLabel on ConsentType {
  String get label {
    switch (this) {
      case ConsentType.privacidad:
        return 'Aviso de privacidad';
      case ConsentType.fotografia:
        return 'Fotografía clínica';
      case ConsentType.desbridamiento:
        return 'Desbridamiento';
    }
  }

  /// Descripción breve del alcance del consentimiento (para la UI de registro).
  String get description {
    switch (this) {
      case ConsentType.privacidad:
        return 'Tratamiento de datos personales y del expediente clínico.';
      case ConsentType.fotografia:
        return 'Toma y uso de fotografía clínica de la(s) herida(s).';
      case ConsentType.desbridamiento:
        return 'Procedimiento de desbridamiento de la herida.';
    }
  }

  String get dbValue => name;

  static ConsentType? fromDb(String s) {
    for (final t in ConsentType.values) {
      if (t.name == s) return t;
    }
    return null;
  }
}

/// Consentimiento informado del paciente para un [ConsentType].
/// Ver migración 0026_consents.sql. Regla de gating (en la app):
/// - valoración + fotografía requieren privacidad + fotografía `granted`.
/// - desbridamiento requiere `desbridamiento` `granted`.
class Consent {
  final String id;
  final String patientId;
  final ConsentType type;
  final bool granted;
  final DateTime? grantedAt;
  final String? signedBy;
  final String? docRef;
  final DateTime createdAt;

  const Consent({
    required this.id,
    required this.patientId,
    required this.type,
    required this.granted,
    this.grantedAt,
    this.signedBy,
    this.docRef,
    required this.createdAt,
  });

  factory Consent.fromJson(Map<String, dynamic> json) => Consent(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        type: ConsentTypeLabel.fromDb(json['type'] as String) ??
            ConsentType.privacidad,
        granted: json['granted'] as bool? ?? false,
        grantedAt: json['granted_at'] == null
            ? null
            : DateTime.parse(json['granted_at'] as String),
        signedBy: json['signed_by'] as String?,
        docRef: json['doc_ref'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'type': type.dbValue,
        'granted': granted,
        'granted_at': grantedAt?.toIso8601String(),
        'signed_by': signedBy,
        'doc_ref': docRef,
        'created_at': createdAt.toIso8601String(),
      };
}
