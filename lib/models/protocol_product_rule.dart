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

  // --- Campos del CATÁLOGO Kura+ (§15). En reglas PROPIAS son null (existen por paridad de
  // esquema, 0136/0140). La MISMA clase sirve las dos fuentes de la Matriz: catálogo (author) y
  // tabla propia (módulo sin Kura+). Una pantalla, dos orígenes.
  final String? contextKind; // etiologia | piel | evolucion | null (= todo)
  final String? contextValue;
  final String? scaleLabel; // referencia (prosa; no gobierna nada)
  final String? triggerLabel;
  final String? brand;
  final String? altName;
  final String? altBrand;
  final String? notePhrase;
  final String? shopifyProductId; // IDENTIDAD (par shopify); null = huérfana con nombre
  final String? shopifyVariantId;
  final String? etapaClinica; // referencia (para la Matriz)
  final String? notas;

  /// Tiene identidad de producto atada (par shopify). Si no, es una huérfana con nombre: la
  /// prosa se ve, pero no aterriza en inventario hasta que un humano la ate (§15 etapa 6.3).
  bool get hasIdentity =>
      shopifyProductId != null && shopifyProductId!.isNotEmpty;

  /// Atada a un INSUMO DEL CENTRO (`inventory_item_id`) — la autoridad del vínculo del
  /// protocolo (Carlos): el protocolo se ata a insumos del centro, NO al catálogo de
  /// Shopify. Un insumo externo (creado a mano, sin par shopify) queda atado por aquí
  /// aunque `hasIdentity` sea falso. `hasIdentity` (par shopify) es SOLO la identidad de
  /// catálogo Kura+ para re-empatar entre centros; el atado que importa es éste.
  bool get isBound =>
      inventoryItemId != null && inventoryItemId!.isNotEmpty;

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
    this.contextKind,
    this.contextValue,
    this.scaleLabel,
    this.triggerLabel,
    this.brand,
    this.altName,
    this.altBrand,
    this.notePhrase,
    this.shopifyProductId,
    this.shopifyVariantId,
    this.etapaClinica,
    this.notas,
  });

  // La resolución (match por medida/exudado/zona/infección, especificidad y
  // cantidad) se retiró de Dart en §15 etapa 3: ahora vive SOLO en SQL
  // (`resolve_protocol`, migración 0139), consultada vía
  // DataRepository.resolveProtocolProductsRpc. Estos campos siguen siendo los
  // que EDITA el catálogo/las reglas; ya no se evalúan en el cliente.

  factory ProtocolProductRule.fromJson(Map<String, dynamic> j) =>
      ProtocolProductRule(
        id: j['id'] as String,
        // El catálogo Kura+ es GLOBAL (sin organization_id) → '' para esas filas; las reglas
        // propias siempre lo traen.
        organizationId: j['organization_id'] as String? ?? '',
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
        contextKind: j['context_kind'] as String?,
        contextValue: j['context_value'] as String?,
        scaleLabel: j['scale_label'] as String?,
        triggerLabel: j['trigger_label'] as String?,
        brand: j['brand'] as String?,
        altName: j['alt_name'] as String?,
        altBrand: j['alt_brand'] as String?,
        notePhrase: j['note_phrase'] as String?,
        shopifyProductId: j['shopify_product_id'] as String?,
        shopifyVariantId: j['shopify_variant_id'] as String?,
        etapaClinica: j['etapa_clinica'] as String?,
        notas: j['notas'] as String?,
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
        'context_kind': contextKind,
        'context_value': contextValue,
        'scale_label': scaleLabel,
        'trigger_label': triggerLabel,
        'brand': brand,
        'alt_name': altName,
        'alt_brand': altBrand,
        'note_phrase': notePhrase,
        'shopify_product_id': shopifyProductId,
        'shopify_variant_id': shopifyVariantId,
        'etapa_clinica': etapaClinica,
        'notas': notas,
      };
}

/// Valor centinela de `source` cuando el RPC NO trae la columna. NO es un valor legítimo del
/// servidor (que emite 'kura' o 'propio'): significa que el contrato se rompió (p. ej. una
/// migración redefinió resolve_protocol sin la columna). Se hace VISIBLE en vez de inventar el
/// valor más inocente ('propio'), que etiquetaría el catálogo como régimen propio — verde y
/// mintiendo. §15 etapa 6.1.
const String kRegimenSourceUnknown = 'desconocido';

/// Rótulo único (3 vías) del régimen que resolvió. Que sea uno solo evita que un flujo mande
/// 'desconocido' al cajón de 'propio' y el otro no.
String regimenSourceLabel(String source) => switch (source) {
      'kura' => 'Régimen Kura+',
      'propio' => 'Protocolo propio del centro',
      _ => 'Régimen desconocido',
    };

/// Producto resuelto para una categoría del protocolo (salida de la resolución).
class ResolvedProtocolProduct {
  final String category; // KuraTag.dbValue
  // NULLABLE desde §15 etapa 5: una regla del catálogo Kura+ sin identidad (o cuya identidad no
  // aterriza en el inventario del centro) se resuelve igual —la PROSA es lo que ve el clínico—
  // pero sin insumo enlazado. Es una huérfana con nombre, no un vacío. El costo/precio/consumo
  // solo aplican cuando hay insumo.
  final String? inventoryItemId;
  final String name;
  final double quantity;
  final double? unitCost;
  final double? unitPrice;
  final String? currency;
  // FUENTE del régimen: 'kura' (catálogo Kura+ curado) o 'propio' (reglas del centro). §15
  // etapa 6.1: la fuente EXISTE en SQL desde 0139/0140 pero nunca se leía. Sin ella, que un
  // centro Kura+ cuyo asiento vence caiga de golpe del catálogo a sus reglas propias sería un
  // cambio en silencio —mismas tarjetas, otro régimen—. Viaja hasta la UI para que la
  // degradación sea OBSERVABLE; no debe existir como camino real sin ser visible. REQUERIDO a
  // propósito: quien construya un resuelto debe declarar de qué régimen salió.
  final String source;
  const ResolvedProtocolProduct({
    required this.category,
    required this.inventoryItemId,
    required this.name,
    required this.quantity,
    required this.source,
    this.unitCost,
    this.unitPrice,
    this.currency,
  });
}

/// La resolución del protocolo NO se pudo consultar: el almacén es local (demo,
/// `LocalStore`) o la llamada al servidor falló (sin conexión). La resolución
/// vive en el servidor desde §15 etapa 3 (`resolve_protocol`); ese movimiento
/// rompe los dos flujos que la usan cuando no hay red. Quien la reciba DEBE
/// decir en pantalla que no pudo traer la sugerencia —un vacío silencioso en una
/// pantalla clínica es peor que un error— en vez de mostrar la pantalla en
/// blanco como si no hubiera nada que sugerir. El soporte offline llega en la
/// etapa 4; aquí solo se hace explícito el hueco.
class ProtocolResolutionUnavailable implements Exception {
  final Object? cause;
  const ProtocolResolutionUnavailable([this.cause]);
  @override
  String toString() => 'ProtocolResolutionUnavailable: $cause';
}
