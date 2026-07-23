/// Cumplimiento de UN tipo de actividad en la ventana (realizadas/esperadas).
class PreventiveComplianceType {
  final String actionId;
  final String title;
  final int done;
  final int expected;
  const PreventiveComplianceType({
    required this.actionId,
    required this.title,
    required this.done,
    required this.expected,
  });
  int get pct => expected == 0 ? 0 : (done * 100 / expected).round();
}

/// Cumplimiento preventivo del paciente en la ventana: por tipo + global.
class PreventiveComplianceResult {
  final List<PreventiveComplianceType> byType;
  final int doneTotal;
  final int expectedTotal;
  const PreventiveComplianceResult({
    required this.byType,
    required this.doneTotal,
    required this.expectedTotal,
  });
  int get globalPct =>
      expectedTotal == 0 ? 0 : (doneTotal * 100 / expectedTotal).round();
  bool get hasExpected => expectedTotal > 0;
}

/// Estado de una tarea preventiva agendada. Ver 0042_preventive_tasks.sql.
enum PreventiveTaskStatus { pending, done, skipped, canceled }

extension PreventiveTaskStatusX on PreventiveTaskStatus {
  String get dbValue => name;
  String get label {
    switch (this) {
      case PreventiveTaskStatus.pending:
        return 'Pendiente';
      case PreventiveTaskStatus.done:
        return 'Hecha';
      case PreventiveTaskStatus.skipped:
        return 'Saltada';
      case PreventiveTaskStatus.canceled:
        return 'Cancelada';
    }
  }

  static PreventiveTaskStatus fromDb(String? s) => PreventiveTaskStatus.values
      .firstWhere((e) => e.name == s, orElse: () => PreventiveTaskStatus.pending);
}

/// Tarea preventiva AGENDADA (fecha + asignado + estado). Autogenerada desde las
/// reglas (cadencias) o creada a mano. Ver 0042_preventive_tasks.sql.
class PreventiveTask {
  final String id;
  final String organizationId;
  final String patientId;
  final String? admissionId;
  final String? ruleId;
  final String? actionId;
  final String title;
  final String? actionLabel;
  final DateTime scheduledAt;
  final String? assigneeProfileId;
  final String assigneeKind; // 'staff' | 'cuidador'
  final PreventiveTaskStatus status;
  final DateTime? doneAt;
  final String? doneBy;
  final String? notes;
  final String source; // 'auto' | 'manual'
  final DateTime createdAt;

  const PreventiveTask({
    required this.id,
    required this.organizationId,
    required this.patientId,
    this.admissionId,
    this.ruleId,
    this.actionId,
    required this.title,
    this.actionLabel,
    required this.scheduledAt,
    this.assigneeProfileId,
    this.assigneeKind = 'staff',
    this.status = PreventiveTaskStatus.pending,
    this.doneAt,
    this.doneBy,
    this.notes,
    this.source = 'auto',
    required this.createdAt,
  });

  bool get isPending => status == PreventiveTaskStatus.pending;

  factory PreventiveTask.fromJson(Map<String, dynamic> json) => PreventiveTask(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String,
        patientId: json['patient_id'] as String,
        admissionId: json['admission_id'] as String?,
        ruleId: json['rule_id'] as String?,
        actionId: json['action_id'] as String?,
        title: json['title'] as String,
        actionLabel: json['action_label'] as String?,
        scheduledAt: DateTime.parse(json['scheduled_at'] as String),
        assigneeProfileId: json['assignee_profile_id'] as String?,
        assigneeKind: (json['assignee_kind'] as String?) ?? 'staff',
        status: PreventiveTaskStatusX.fromDb(json['status'] as String?),
        doneAt: json['done_at'] == null ? null : DateTime.parse(json['done_at'] as String),
        doneBy: json['done_by'] as String?,
        notes: json['notes'] as String?,
        source: (json['source'] as String?) ?? 'auto',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'patient_id': patientId,
        'admission_id': admissionId,
        'rule_id': ruleId,
        'action_id': actionId,
        'title': title,
        'action_label': actionLabel,
        'scheduled_at': scheduledAt.toIso8601String(),
        'assignee_profile_id': assigneeProfileId,
        'assignee_kind': assigneeKind,
        'status': status.dbValue,
        'done_at': doneAt?.toIso8601String(),
        'done_by': doneBy,
        'notes': notes,
        'source': source,
        'created_at': createdAt.toIso8601String(),
      };
}
