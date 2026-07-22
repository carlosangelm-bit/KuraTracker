/// Registro de una acción preventiva realizada (módulo de Prevención). Deja
/// constancia (fecha + autor) de la medida aplicada. Append-only: cada
/// aplicación es una fila. `ruleId`/`actionId` referencian el asset
/// prevention_rules.json. Ver migración 0037_preventive_action_log.sql.
class PreventiveActionLog {
  final String id;
  final String? organizationId;
  final String patientId;
  final String ruleId;
  final String actionId;
  final String actionLabel; // snapshot
  final DateTime appliedAt;
  final String? appliedBy; // staff.id
  final String? notes;
  final DateTime? createdAt;

  const PreventiveActionLog({
    required this.id,
    this.organizationId,
    required this.patientId,
    required this.ruleId,
    required this.actionId,
    required this.actionLabel,
    required this.appliedAt,
    this.appliedBy,
    this.notes,
    this.createdAt,
  });

  factory PreventiveActionLog.fromJson(Map<String, dynamic> json) =>
      PreventiveActionLog(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String?,
        patientId: json['patient_id'] as String,
        ruleId: json['rule_id'] as String,
        actionId: json['action_id'] as String,
        actionLabel: json['action_label'] as String,
        appliedAt: DateTime.parse(json['applied_at'] as String),
        appliedBy: json['applied_by'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'patient_id': patientId,
        'rule_id': ruleId,
        'action_id': actionId,
        'action_label': actionLabel,
        'applied_at': appliedAt.toIso8601String(),
        'applied_by': appliedBy,
        'notes': notes,
        'created_at': createdAt?.toIso8601String(),
      };
}
