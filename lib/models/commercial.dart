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
  // Pago externo (Mercado Pago Point, migr 0055).
  final String? paymentProvider; // 'manual' | 'mercadopago'
  final String? externalReference; // ref enviada a la terminal
  final String? mpPaymentId;
  final String? mpStatus;

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
    this.paymentProvider,
    this.externalReference,
    this.mpPaymentId,
    this.mpStatus,
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
        paymentProvider: j['payment_provider'] as String?,
        externalReference: j['external_reference'] as String?,
        mpPaymentId: j['mp_payment_id'] as String?,
        mpStatus: j['mp_status'] as String?,
      );
}

/// Pago entrante de una terminal Mercado Pago Point (bandeja de conciliación,
/// migr 0055). Si [chargeId] es null, aún no está ligado a un cobro.
class PointPayment {
  final String id;
  final String organizationId;
  final String? mpPaymentId;
  final double amount;
  final String currency;
  final String status; // approved | rejected | refunded | pending
  final String? method; // credit_card | debit_card | ...
  final String? externalReference;
  final String? deviceId;
  final String? description;
  final DateTime? capturedAt;
  final String? chargeId; // null = sin ligar
  final String? linkedBy;
  final DateTime? linkedAt;
  final String source; // manual | webhook
  final DateTime createdAt;

  const PointPayment({
    required this.id,
    required this.organizationId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.currency = 'MXN',
    this.mpPaymentId,
    this.method,
    this.externalReference,
    this.deviceId,
    this.description,
    this.capturedAt,
    this.chargeId,
    this.linkedBy,
    this.linkedAt,
    this.source = 'manual',
  });

  bool get isLinked => chargeId != null;

  factory PointPayment.fromJson(Map<String, dynamic> j) => PointPayment(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        mpPaymentId: j['mp_payment_id'] as String?,
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] as String? ?? 'MXN',
        status: j['status'] as String? ?? 'approved',
        method: j['method'] as String?,
        externalReference: j['external_reference'] as String?,
        deviceId: j['device_id'] as String?,
        description: j['description'] as String?,
        capturedAt: j['captured_at'] == null
            ? null
            : DateTime.tryParse('${j['captured_at']}')?.toLocal(),
        chargeId: j['charge_id'] as String?,
        linkedBy: j['linked_by'] as String?,
        linkedAt: j['linked_at'] == null
            ? null
            : DateTime.tryParse('${j['linked_at']}')?.toLocal(),
        source: j['source'] as String? ?? 'manual',
        createdAt:
            DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
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
