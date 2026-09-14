/// Un derecho de `org_entitlements` con sus campos de otorgamiento (0113 + 0132),
/// para la consola master. Modelo de LECTURA: la escritura pasa por las RPC
/// master_* (nunca un insert/update directo desde la app).
class OrgEntitlement {
  final String id;
  final String organizationId;
  final String kind; // 'plan' | 'module' | 'seat'
  final String key;
  final int? quantity; // solo kind='seat'
  final String status; // 'active' | 'past_due' | 'canceled'
  final DateTime? currentPeriodEnd; // vencimiento; null = no vence
  final String source; // 'stripe' | 'master'
  final String? grantType; // 'comercial' | 'cortesia'; null si stripe
  final String? reason;
  final String? grantedBy;
  final bool isPermanent;

  const OrgEntitlement({
    required this.id,
    required this.organizationId,
    required this.kind,
    required this.key,
    required this.quantity,
    required this.status,
    required this.currentPeriodEnd,
    required this.source,
    required this.grantType,
    required this.reason,
    required this.grantedBy,
    required this.isPermanent,
  });

  bool get isMaster => source == 'master';
  bool get isActive => status == 'active';

  factory OrgEntitlement.fromJson(Map<String, dynamic> j) => OrgEntitlement(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        kind: j['kind'] as String,
        key: j['key'] as String,
        quantity: (j['quantity'] as num?)?.toInt(),
        status: j['status'] as String? ?? 'active',
        currentPeriodEnd: j['current_period_end'] == null
            ? null
            : DateTime.tryParse('${j['current_period_end']}')?.toLocal(),
        source: j['source'] as String? ?? 'master',
        grantType: j['grant_type'] as String?,
        reason: j['reason'] as String?,
        grantedBy: j['granted_by'] as String?,
        isPermanent: j['is_permanent'] as bool? ?? false,
      );
}

/// Un derecho otorgado a mano (source='master'), con el nombre de su centro, para
/// la pantalla "Otorgados a mano" (§5.5). Se ordena vencidos primero, luego por
/// vencimiento ascendente, permanentes al final.
class ManualGrant {
  final OrgEntitlement entitlement;
  final String organizationName;

  const ManualGrant({required this.entitlement, required this.organizationName});

  String get organizationId => entitlement.organizationId;
  bool get isPermanent => entitlement.isPermanent;
  DateTime? get currentPeriodEnd => entitlement.currentPeriodEnd;

  /// Vencido = tiene fecha y ya pasó. Los permanentes nunca vencen.
  bool get isExpired {
    final end = currentPeriodEnd;
    return !isPermanent && end != null && !end.isAfter(DateTime.now());
  }
}
