/// Servicio del catálogo del centro con su honorario (módulo comercial, Fase C).
class ServiceCatalogItem {
  final String id;
  final String organizationId;
  final String name;
  final double price;
  final String currency;
  final bool isActive;

  const ServiceCatalogItem({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.price,
    this.currency = 'MXN',
    this.isActive = true,
  });

  factory ServiceCatalogItem.fromJson(Map<String, dynamic> j) => ServiceCatalogItem(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        name: j['name'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] as String? ?? 'MXN',
        isActive: j['is_active'] as bool? ?? true,
      );
}

enum ChargeStatus { pendiente, pagado, cancelado }

extension ChargeStatusX on ChargeStatus {
  String get dbValue => name;
  String get label {
    switch (this) {
      case ChargeStatus.pendiente:
        return 'Pendiente';
      case ChargeStatus.pagado:
        return 'Pagado';
      case ChargeStatus.cancelado:
        return 'Cancelado';
    }
  }

  static ChargeStatus fromDb(String? s) => ChargeStatus.values
      .firstWhere((e) => e.name == s, orElse: () => ChargeStatus.pendiente);
}

/// Cobro de una consulta = honorario del servicio + insumos marcados "cobrar".
class Charge {
  final String id;
  final String organizationId;
  final String? patientId;
  final String? consultationId;
  final String? siteId;
  final double subtotalService;
  final double subtotalSupplies;
  final double total;
  final String currency;
  final ChargeStatus status;
  final String? paymentMethod;
  final DateTime? paidAt;
  final String? notes;
  final DateTime createdAt;

  const Charge({
    required this.id,
    required this.organizationId,
    required this.total,
    required this.status,
    required this.createdAt,
    this.patientId,
    this.consultationId,
    this.siteId,
    this.subtotalService = 0,
    this.subtotalSupplies = 0,
    this.currency = 'MXN',
    this.paymentMethod,
    this.paidAt,
    this.notes,
  });

  factory Charge.fromJson(Map<String, dynamic> j) => Charge(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        patientId: j['patient_id'] as String?,
        consultationId: j['consultation_id'] as String?,
        siteId: j['site_id'] as String?,
        subtotalService: (j['subtotal_service'] as num?)?.toDouble() ?? 0,
        subtotalSupplies: (j['subtotal_supplies'] as num?)?.toDouble() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] as String? ?? 'MXN',
        status: ChargeStatusX.fromDb(j['status'] as String?),
        paymentMethod: j['payment_method'] as String?,
        paidAt: j['paid_at'] == null ? null : DateTime.tryParse('${j['paid_at']}')?.toLocal(),
        notes: j['notes'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
      );
}

/// Renglón del desglose de un cobro (servicio o insumo).
class ChargeItem {
  final String id;
  final String chargeId;
  final String organizationId;
  final String kind; // 'servicio' | 'insumo'
  final String name;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const ChargeItem({
    required this.id,
    required this.chargeId,
    required this.organizationId,
    required this.kind,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory ChargeItem.fromJson(Map<String, dynamic> j) => ChargeItem(
        id: j['id'] as String,
        chargeId: j['charge_id'] as String,
        organizationId: j['organization_id'] as String,
        kind: j['kind'] as String? ?? 'insumo',
        name: j['name'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0,
        lineTotal: (j['line_total'] as num?)?.toDouble() ?? 0,
      );
}
