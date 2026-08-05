// Regla producto-por-categoría del protocolo (ver 0076_protocol_product_rules).
// Resuelve el producto concreto + cantidad según la MEDIDA de la herida.
// `category` guarda el KuraTag.dbValue (aposito, relleno_cavidad, ...).

/// Grupos de zona anatómica para las reglas (agrupan bodyLocationPrimary).
class ZoneGroup {
  static const sacroGluteo = 'sacro_gluteo';
  static const talonPie = 'talon_pie';
  static const piernaMmii = 'pierna_mmii';
  static const tronco = 'tronco';
  static const otro = 'otro';

  static const all = [sacroGluteo, talonPie, piernaMmii, tronco, otro];

  static String label(String key) => switch (key) {
        sacroGluteo => 'Sacro / glúteo',
        talonPie => 'Talón / pie',
        piernaMmii => 'Pierna / MMII',
        tronco => 'Tronco',
        _ => 'Otro',
      };

  /// Mapea una localización (texto/código de bodyLocationPrimary) a su grupo,
  /// por palabras clave (mismo enfoque heurístico que ya usa el capture).
  static String forLocation(String? loc) {
    final s = (loc ?? '').toLowerCase();
    if (s.contains('sacr') || s.contains('glut') || s.contains('isqui') ||
        s.contains('coxis') || s.contains('trocanter') || s.contains('trocánter')) {
      return sacroGluteo;
    }
    if (s.contains('talon') || s.contains('talón') || s.contains('pie') ||
        s.contains('ortejo') || s.contains('dedo') || s.contains('metatars') ||
        s.contains('plantar') || s.contains('maleol')) {
      return talonPie;
    }
    if (s.contains('pierna') || s.contains('tibia') || s.contains('gemelo') ||
        s.contains('pantorr') || s.contains('rodilla') || s.contains('mmii') ||
        s.contains('muslo')) {
      return piernaMmii;
    }
    if (s.contains('tronco') || s.contains('abdom') || s.contains('torax') ||
        s.contains('tórax') || s.contains('espalda') || s.contains('dorsal') ||
        s.contains('mama')) {
      return tronco;
    }
    return otro;
  }
}

enum RuleInfection { any, yes, no }

RuleInfection ruleInfectionFromDb(String? s) => switch (s) {
      'yes' => RuleInfection.yes,
      'no' => RuleInfection.no,
      _ => RuleInfection.any,
    };

extension RuleInfectionX on RuleInfection {
  String get dbValue => switch (this) {
        RuleInfection.yes => 'yes',
        RuleInfection.no => 'no',
        RuleInfection.any => 'any',
      };
  String get label => switch (this) {
        RuleInfection.yes => 'Con infección/riesgo',
        RuleInfection.no => 'Sin infección',
        RuleInfection.any => 'Cualquiera',
      };
}

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
  // Condiciones multi-factor (0077). Listas vacías = "cualquiera".
  final List<String> exudateLevels; // ExudadoCantidad.name
  final List<String> zoneGroups; // ZoneGroup keys
  final RuleInfection infection;
  final int priority;

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
    this.exudateLevels = const [],
    this.zoneGroups = const [],
    this.infection = RuleInfection.any,
    this.priority = 0,
  });

  /// La regla aplica si TODAS sus condiciones se cumplen. Una condición con
  /// valor no provisto (null) hace que la regla NO aplique (fail-safe: no se
  /// sugiere un producto condicionado si falta el dato).
  bool appliesTo({
    double? areaCm2,
    double? volumeCm3,
    String? exudateLevel,
    String? zoneGroup,
    bool? infectionSuspected,
  }) {
    // Medida (área/volumen)
    if (dimension != RuleDimension.none) {
      final v = dimension == RuleDimension.area ? areaCm2 : volumeCm3;
      if (v == null) return false;
      if (minValue != null && v < minValue!) return false;
      if (maxValue != null && v >= maxValue!) return false; // [min, max)
    }
    // Exudado
    if (exudateLevels.isNotEmpty) {
      if (exudateLevel == null || !exudateLevels.contains(exudateLevel)) {
        return false;
      }
    }
    // Zona anatómica
    if (zoneGroups.isNotEmpty) {
      if (zoneGroup == null || !zoneGroups.contains(zoneGroup)) return false;
    }
    // Infección / riesgo
    if (infection != RuleInfection.any) {
      if (infectionSuspected == null) return false;
      if (infection == RuleInfection.yes && !infectionSuspected) return false;
      if (infection == RuleInfection.no && infectionSuspected) return false;
    }
    return true;
  }

  /// Cuántas condiciones tiene activas (para elegir la regla más específica).
  int get specificity {
    var n = 0;
    if (dimension != RuleDimension.none) n++;
    if (exudateLevels.isNotEmpty) n++;
    if (zoneGroups.isNotEmpty) n++;
    if (infection != RuleInfection.any) n++;
    return n;
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
        exudateLevels: ((j['exudate_levels'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        zoneGroups: ((j['zone_groups'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        infection: ruleInfectionFromDb(j['infection'] as String?),
        priority: (j['priority'] as num?)?.toInt() ?? 0,
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
        'exudate_levels': exudateLevels,
        'zone_groups': zoneGroups,
        'infection': infection.dbValue,
        'priority': priority,
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
