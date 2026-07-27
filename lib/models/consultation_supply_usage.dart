/// Insumo utilizado en una consulta, con banderas independientes: [charge]
/// (se cobra al paciente) y [discount] (se descuenta del inventario). Ver
/// 0051_consultation_supply_usage.sql (módulo Insumos, Fase B).
class ConsultationSupplyUsage {
  final String id;
  final String organizationId;
  final String consultationId;
  final String? patientId;
  final String? inventoryItemId;
  final String name;
  final int quantity;
  final bool charge;
  final bool discount;
  final double? unitCost; // costo (para costeo interno / descuento)
  final double? unitPrice; // precio de venta (lo que se cobra al paciente)
  final String? currency;
  final bool discounted; // ya se materializó la salida de inventario

  const ConsultationSupplyUsage({
    required this.id,
    required this.organizationId,
    required this.consultationId,
    required this.name,
    this.patientId,
    this.inventoryItemId,
    this.quantity = 1,
    this.charge = true,
    this.discount = true,
    this.unitCost,
    this.unitPrice,
    this.currency,
    this.discounted = false,
  });

  /// Importe a COBRAR de la línea (precio × cantidad; si no hay precio, costo).
  double get lineTotal => (unitPrice ?? unitCost ?? 0) * quantity;

  factory ConsultationSupplyUsage.fromJson(Map<String, dynamic> j) =>
      ConsultationSupplyUsage(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        consultationId: j['consultation_id'] as String,
        patientId: j['patient_id'] as String?,
        inventoryItemId: j['inventory_item_id'] as String?,
        name: j['name'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        charge: j['charge'] as bool? ?? true,
        discount: j['discount'] as bool? ?? true,
        unitCost: (j['unit_cost'] as num?)?.toDouble(),
        unitPrice: (j['unit_price'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        discounted: j['discounted'] as bool? ?? false,
      );
}
