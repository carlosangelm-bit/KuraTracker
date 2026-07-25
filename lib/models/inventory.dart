/// Artículo de inventario de un sitio (módulo Insumos, Fase 3). Puede ser un
/// producto de la tienda Kura+ (con ids de Shopify) o un producto EXTERNO
/// capturado a mano. Ver 0050_inventory.sql.
class InventoryItem {
  final String id;
  final String organizationId;
  final String siteId;
  final String name;
  final bool isExternal;
  final String? shopifyProductId;
  final String? shopifyVariantId;
  final String? imageUrl;
  final double? unitCost;
  final String? currency;
  final String? supplier;
  final int? reorderThreshold;
  final String? notes;
  final bool isActive;

  const InventoryItem({
    required this.id,
    required this.organizationId,
    required this.siteId,
    required this.name,
    this.isExternal = false,
    this.shopifyProductId,
    this.shopifyVariantId,
    this.imageUrl,
    this.unitCost,
    this.currency,
    this.supplier,
    this.reorderThreshold,
    this.notes,
    this.isActive = true,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        siteId: j['site_id'] as String,
        name: j['name'] as String? ?? '',
        isExternal: j['is_external'] as bool? ?? false,
        shopifyProductId: j['shopify_product_id'] as String?,
        shopifyVariantId: j['shopify_variant_id'] as String?,
        imageUrl: j['image_url'] as String?,
        unitCost: (j['unit_cost'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        supplier: j['supplier'] as String?,
        reorderThreshold: (j['reorder_threshold'] as num?)?.toInt(),
        notes: j['notes'] as String?,
        isActive: j['is_active'] as bool? ?? true,
      );
}

/// Motivo de un movimiento de inventario.
enum InventoryReason { compra, consumo, ajuste, merma, conteo, devolucion }

extension InventoryReasonX on InventoryReason {
  String get dbValue => name;
  String get label {
    switch (this) {
      case InventoryReason.compra:
        return 'Compra / reabasto';
      case InventoryReason.consumo:
        return 'Consumo';
      case InventoryReason.ajuste:
        return 'Ajuste';
      case InventoryReason.merma:
        return 'Merma';
      case InventoryReason.conteo:
        return 'Conteo físico';
      case InventoryReason.devolucion:
        return 'Devolución';
    }
  }

  static InventoryReason fromDb(String? s) => InventoryReason.values
      .firstWhere((e) => e.name == s, orElse: () => InventoryReason.ajuste);
}

/// Movimiento de inventario (entrada +, salida −). Ver 0050_inventory.sql.
class InventoryMovement {
  final String id;
  final String organizationId;
  final String siteId;
  final String inventoryItemId;
  final int delta;
  final InventoryReason reason;
  final double? unitCost;
  final String? patientId;
  final String? consultationId;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;

  const InventoryMovement({
    required this.id,
    required this.organizationId,
    required this.siteId,
    required this.inventoryItemId,
    required this.delta,
    required this.reason,
    required this.createdAt,
    this.unitCost,
    this.patientId,
    this.consultationId,
    this.note,
    this.createdBy,
  });

  factory InventoryMovement.fromJson(Map<String, dynamic> j) => InventoryMovement(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        siteId: j['site_id'] as String,
        inventoryItemId: j['inventory_item_id'] as String,
        delta: (j['delta'] as num?)?.toInt() ?? 0,
        reason: InventoryReasonX.fromDb(j['reason'] as String?),
        unitCost: (j['unit_cost'] as num?)?.toDouble(),
        patientId: j['patient_id'] as String?,
        consultationId: j['consultation_id'] as String?,
        note: j['note'] as String?,
        createdBy: j['created_by'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ??
            DateTime.now(),
      );
}
