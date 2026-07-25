/// Mapeo de un insumo GENÉRICO del protocolo (método + producto genérico) a un
/// PRODUCTO concreto de la tienda Shopify, por centro. Guarda una foto del
/// producto (título/imagen/precio) para mostrar sin llamar a Shopify.
/// Ver 0048_supply_product_mappings.sql (módulo Insumos, Fase 2 premium).
class SupplyProductMapping {
  final String id;
  final String organizationId;
  final String method; // 'Apósito'
  final String genericProduct; // 'Espuma con borde adhesivo'
  final String shopifyProductId; // gid://shopify/Product/...
  final String? shopifyVariantId;
  final String shopifyTitle; // 'Mepilex Border 10x10'
  final String? shopifyVariantTitle;
  final String? shopifyHandle;
  final String? imageUrl;
  final double? priceAmount;
  final String? priceCurrency;

  const SupplyProductMapping({
    required this.id,
    required this.organizationId,
    required this.method,
    required this.genericProduct,
    required this.shopifyProductId,
    required this.shopifyTitle,
    this.shopifyVariantId,
    this.shopifyVariantTitle,
    this.shopifyHandle,
    this.imageUrl,
    this.priceAmount,
    this.priceCurrency,
  });

  /// Clave única del insumo genérico (para agrupar/buscar mapeos).
  static String keyFor(String method, String genericProduct) =>
      '$method::$genericProduct';
  String get key => keyFor(method, genericProduct);

  factory SupplyProductMapping.fromJson(Map<String, dynamic> j) =>
      SupplyProductMapping(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        method: j['method'] as String,
        genericProduct: j['generic_product'] as String,
        shopifyProductId: j['shopify_product_id'] as String,
        shopifyVariantId: j['shopify_variant_id'] as String?,
        shopifyTitle: j['shopify_title'] as String? ?? '',
        shopifyVariantTitle: j['shopify_variant_title'] as String?,
        shopifyHandle: j['shopify_handle'] as String?,
        imageUrl: j['image_url'] as String?,
        priceAmount: (j['price_amount'] as num?)?.toDouble(),
        priceCurrency: j['price_currency'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'method': method,
        'generic_product': genericProduct,
        'shopify_product_id': shopifyProductId,
        'shopify_variant_id': shopifyVariantId,
        'shopify_title': shopifyTitle,
        'shopify_variant_title': shopifyVariantTitle,
        'shopify_handle': shopifyHandle,
        'image_url': imageUrl,
        'price_amount': priceAmount,
        'price_currency': priceCurrency,
      };
}
