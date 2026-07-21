/// Gravedad de un evento adverso (Protocolo "Manejo de eventos adversos").
/// `centinela` es el nivel máximo: exige reporte a la autoridad en <=24 h.
enum AdverseEventSeverity { leve, moderado, grave, centinela }

extension AdverseEventSeverityLabel on AdverseEventSeverity {
  String get label {
    switch (this) {
      case AdverseEventSeverity.leve:
        return 'Leve';
      case AdverseEventSeverity.moderado:
        return 'Moderado';
      case AdverseEventSeverity.grave:
        return 'Grave';
      case AdverseEventSeverity.centinela:
        return 'Centinela';
    }
  }

  String get dbValue => name;

  static AdverseEventSeverity fromDb(String s) =>
      AdverseEventSeverity.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AdverseEventSeverity.leve,
      );
}

/// Señales de alarma del checklist (Protocolo "Manejo de eventos adversos").
/// Se persisten como objeto JSON booleano en `adverse_events.alarm_signs`
/// (clave = [jsonKey]); es extensible sin migración.
enum AdverseEventAlarmSign {
  fiebre38,
  sangrado10min,
  linfangitis,
  signosSistemicos,
}

extension AdverseEventAlarmSignLabel on AdverseEventAlarmSign {
  String get jsonKey {
    switch (this) {
      case AdverseEventAlarmSign.fiebre38:
        return 'fiebre_38';
      case AdverseEventAlarmSign.sangrado10min:
        return 'sangrado_10min';
      case AdverseEventAlarmSign.linfangitis:
        return 'linfangitis';
      case AdverseEventAlarmSign.signosSistemicos:
        return 'signos_sistemicos';
    }
  }

  String get label {
    switch (this) {
      case AdverseEventAlarmSign.fiebre38:
        return 'Fiebre ≥38°';
      case AdverseEventAlarmSign.sangrado10min:
        return 'Sangrado >10 min';
      case AdverseEventAlarmSign.linfangitis:
        return 'Linfangitis';
      case AdverseEventAlarmSign.signosSistemicos:
        return 'Signos sistémicos';
    }
  }

  static AdverseEventAlarmSign? fromKey(String key) {
    for (final s in AdverseEventAlarmSign.values) {
      if (s.jsonKey == key) return s;
    }
    return null;
  }
}

/// Ventana regulatoria de reporte para un evento centinela (COFEPRIS): 24 h
/// desde la ocurrencia del evento.
const Duration kCentinelaReportWindow = Duration(hours: 24);

/// Un evento adverso registrado durante el seguimiento de una herida.
/// Ligado siempre a un paciente y opcionalmente a la herida/consulta donde se
/// detectó. Ver migración 0025_adverse_events.sql.
class AdverseEvent {
  final String id;
  final String organizationId;
  final String patientId;
  final String? woundId;
  final String? consultationId;
  final String? staffId;
  final DateTime occurredAt;
  final String type;
  final AdverseEventSeverity severity;
  final Set<AdverseEventAlarmSign> alarmSigns;
  final String? description;
  final String? actionsTaken;
  final String? evolution;
  final DateTime? reportedAt;
  final DateTime createdAt;

  const AdverseEvent({
    required this.id,
    required this.organizationId,
    required this.patientId,
    this.woundId,
    this.consultationId,
    this.staffId,
    required this.occurredAt,
    required this.type,
    required this.severity,
    this.alarmSigns = const {},
    this.description,
    this.actionsTaken,
    this.evolution,
    this.reportedAt,
    required this.createdAt,
  });

  /// Evento centinela: máxima gravedad, exige reporte <=24 h.
  bool get isCentinela => severity == AdverseEventSeverity.centinela;

  /// true si ya se reportó a la autoridad.
  bool get isReported => reportedAt != null;

  /// Vencimiento del reporte regulatorio (solo aplica a centinela).
  DateTime get reportDeadline => occurredAt.add(kCentinelaReportWindow);

  /// Evento centinela aún sin reportar: requiere la marca de alerta y el
  /// recordatorio de reporte.
  bool get needsReport => isCentinela && !isReported;

  /// true si el evento centinela sigue pendiente y ya venció la ventana de
  /// 24 h respecto a [now]. Se pasa `now` explícitamente para que la lógica
  /// sea determinística y testeable.
  bool isReportOverdue(DateTime now) =>
      needsReport && now.isAfter(reportDeadline);

  /// Tiempo restante hasta el vencimiento del reporte respecto a [now].
  /// Negativo si ya venció. Solo significativo cuando [needsReport] es true.
  Duration timeToReportDeadline(DateTime now) => reportDeadline.difference(now);

  factory AdverseEvent.fromJson(Map<String, dynamic> json) {
    final rawSigns = (json['alarm_signs'] as Map?) ?? const {};
    final signs = <AdverseEventAlarmSign>{};
    rawSigns.forEach((k, v) {
      if (v == true) {
        final sign = AdverseEventAlarmSignLabel.fromKey(k as String);
        if (sign != null) signs.add(sign);
      }
    });

    return AdverseEvent(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      patientId: json['patient_id'] as String,
      woundId: json['wound_id'] as String?,
      consultationId: json['consultation_id'] as String?,
      staffId: json['staff_id'] as String?,
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      type: json['type'] as String,
      severity: AdverseEventSeverityLabel.fromDb(json['severity'] as String),
      alarmSigns: signs,
      description: json['description'] as String?,
      actionsTaken: json['actions_taken'] as String?,
      evolution: json['evolution'] as String?,
      reportedAt: json['reported_at'] == null
          ? null
          : DateTime.parse(json['reported_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Serializa el checklist como objeto JSON booleano con TODAS las claves
  /// canónicas (true/false), para que el registro sea explícito y auditable.
  Map<String, bool> alarmSignsJson() => {
        for (final s in AdverseEventAlarmSign.values)
          s.jsonKey: alarmSigns.contains(s),
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'patient_id': patientId,
        'wound_id': woundId,
        'consultation_id': consultationId,
        'staff_id': staffId,
        'occurred_at': occurredAt.toIso8601String(),
        'type': type,
        'severity': severity.dbValue,
        'alarm_signs': alarmSignsJson(),
        'description': description,
        'actions_taken': actionsTaken,
        'evolution': evolution,
        'reported_at': reportedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}
