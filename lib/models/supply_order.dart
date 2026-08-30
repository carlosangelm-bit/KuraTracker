/// Pedido de insumos (0095): lo que un centro pidió (típicamente a Kura+) y
/// contra lo cual cierra la recepción. Alcance acotado: pedido → recibido
/// (total o parcial). El pedido pertenece al CENTRO que compra.
class SupplyOrderItem {
  final String id;
  final String orderId;
  final String organizationId;
  final String? inventoryItemId;
  final String name; // snapshot
  final int quantityOrdered;
  final int quantityReceived;

  const SupplyOrderItem({
    required this.id,
    required this.orderId,
    required this.organizationId,
    this.inventoryItemId,
    required this.name,
    required this.quantityOrdered,
    this.quantityReceived = 0,
  });

  int get pending =>
      (quantityOrdered - quantityReceived).clamp(0, quantityOrdered);
  bool get fullyReceived => quantityReceived >= quantityOrdered;

  factory SupplyOrderItem.fromJson(Map<String, dynamic> j) => SupplyOrderItem(
        id: j['id'] as String,
        orderId: j['order_id'] as String,
        organizationId: j['organization_id'] as String,
        inventoryItemId: j['inventory_item_id'] as String?,
        name: j['name'] as String,
        quantityOrdered: (j['quantity_ordered'] as num).toInt(),
        quantityReceived: (j['quantity_received'] as num?)?.toInt() ?? 0,
      );
}

class SupplyOrder {
  final String id;
  final String organizationId;
  final String? siteId;
  final String status; // pendiente | parcial | recibido | cancelado
  final String? notes;
  final DateTime createdAt;
  final List<SupplyOrderItem> items;

  const SupplyOrder({
    required this.id,
    required this.organizationId,
    this.siteId,
    required this.status,
    this.notes,
    required this.createdAt,
    this.items = const [],
  });

  bool get isOpen => status == 'pendiente' || status == 'parcial';

  factory SupplyOrder.fromJson(Map<String, dynamic> j,
          {List<SupplyOrderItem> items = const []}) =>
      SupplyOrder(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        siteId: j['site_id'] as String?,
        status: j['status'] as String? ?? 'pendiente',
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        items: items,
      );
}
