// Regla producto-por-categoría del protocolo (ver 0076_protocol_product_rules).
// Resuelve el producto concreto + cantidad según la MEDIDA de la herida.
// `category` guarda el KuraTag.dbValue (aposito, relleno_cavidad, ...).

enum RuleDimension { none, area, volume }

RuleDimension ruleDimensionFromDb(String? s) => switch (s) {
      'area' => RuleDimension.area,
      'volume' => RuleDimension.volume,
      _ => RuleDimension.none,
    };

extension RuleDimensionX on RuleDimension {
  String get dbValue => switch (this) {
        RuleDimension.area => 'area',
        RuleDimension.volume => 'volume',
        RuleDimension.none => 'none',
      };
  String get label => switch (this) {
        RuleDimension.area => 'Área (cm²)',
        RuleDimension.volume => 'Volumen (cm³)',
        RuleDimension.none => 'Sin medida',
      };
}

enum QuantityMode { fixed, perArea, perVolume }

QuantityMode quantityModeFromDb(String? s) => switch (s) {
      'per_area' => QuantityMode.perArea,
      'per_volume' => QuantityMode.perVolume,
      _ => QuantityMode.fixed,
    };

extension QuantityModeX on QuantityMode {
  String get dbValue => switch (this) {
        QuantityMode.perArea => 'per_area',
        QuantityMode.perVolume => 'per_volume',
        QuantityMode.fixed => 'fixed',
      };
  String get label => switch (this) {
        QuantityMode.perArea => 'Por área (× cm²)',
        QuantityMode.perVolume => 'Por volumen (× cm³)',
        QuantityMode.fixed => 'Cantidad fija',
      };
}

class ProtocolProductRule {
  final String id;
  final String organizationId;
  final String category; // KuraTag.dbValue
  final String? inventoryItemId;
  final String? name;
  final RuleDimension dimension;
  final double? minValue;
  final double? maxValue;
  final QuantityMode quantityMode;
  final double quantityValue;
  final int sortOrder;

  const ProtocolProductRule({
    required this.id,
    required this.organizationId,
    required this.category,
    this.inventoryItemId,
    this.name,
    this.dimension = RuleDimension.none,
    this.minValue,
    this.maxValue,
    this.quantityMode = QuantityMode.fixed,
    this.quantityValue = 1,
    this.sortOrder = 0,
  });

  /// La regla aplica para una medida dada (área o volumen, según su dimensión).
  bool appliesTo({double? areaCm2, double? volumeCm3}) {
    if (dimension == RuleDimension.none) return true;
    final v = dimension == RuleDimension.area ? areaCm2 : volumeCm3;
    if (v == null) return false;
    if (minValue != null && v < minValue!) return false;
    if (maxValue != null && v >= maxValue!) return false; // [min, max)
    return true;
  }

  /// Cantidad resuelta según el modo y la medida.
  double quantityFor({double? areaCm2, double? volumeCm3}) => switch (quantityMode) {
        QuantityMode.perArea => (areaCm2 ?? 0) * quantityValue,
        QuantityMode.perVolume => (volumeCm3 ?? 0) * quantityValue,
        QuantityMode.fixed => quantityValue,
      };

  factory ProtocolProductRule.fromJson(Map<String, dynamic> j) =>
      ProtocolProductRule(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        category: j['category'] as String? ?? '',
        inventoryItemId: j['inventory_item_id'] as String?,
        name: j['name'] as String?,
        dimension: ruleDimensionFromDb(j['dimension'] as String?),
        minValue: (j['min_value'] as num?)?.toDouble(),
        maxValue: (j['max_value'] as num?)?.toDouble(),
        quantityMode: quantityModeFromDb(j['quantity_mode'] as String?),
        quantityValue: (j['quantity_value'] as num?)?.toDouble() ?? 1,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'category': category,
        'inventory_item_id': inventoryItemId,
        'name': name,
        'dimension': dimension.dbValue,
        'min_value': minValue,
        'max_value': maxValue,
        'quantity_mode': quantityMode.dbValue,
        'quantity_value': quantityValue,
        'sort_order': sortOrder,
      };
}

/// Producto resuelto para una categoría del protocolo (salida de la resolución).
class ResolvedProtocolProduct {
  final String category; // KuraTag.dbValue
  final String inventoryItemId;
  final String name;
  final double quantity;
  final double? unitCost;
  final double? unitPrice;
  final String? currency;
  const ResolvedProtocolProduct({
    required this.category,
    required this.inventoryItemId,
    required this.name,
    required this.quantity,
    this.unitCost,
    this.unitPrice,
    this.currency,
  });
}
