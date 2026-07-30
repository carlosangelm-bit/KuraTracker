// Producto del catálogo GLOBAL (sembrado desde Shopify). Ver 0067_product_catalog.sql.
class ProductCatalogItem {
  final String id;
  final String shopifyProductId;
  final String? shopifyVariantId;
  final String? sku;
  final String title;
  final String? variantTitle;
  final String? vendor;
  final String? productType;
  final double? price;
  final String? currency;
  final String? imageUrl;
  final bool isActive;

  const ProductCatalogItem({
    required this.id,
    required this.shopifyProductId,
    this.shopifyVariantId,
    this.sku,
    required this.title,
    this.variantTitle,
    this.vendor,
    this.productType,
    this.price,
    this.currency,
    this.imageUrl,
    this.isActive = true,
  });

  /// Nombre legible: título + presentación cuando aplica.
  String get displayName => (variantTitle == null ||
          variantTitle!.isEmpty ||
          variantTitle == 'Default Title')
      ? title
      : '$title · $variantTitle';

  factory ProductCatalogItem.fromJson(Map<String, dynamic> j) =>
      ProductCatalogItem(
        id: j['id'] as String,
        shopifyProductId: j['shopify_product_id'] as String,
        shopifyVariantId: (j['shopify_variant_id'] as String?)?.isEmpty ?? true
            ? null
            : j['shopify_variant_id'] as String?,
        sku: j['sku'] as String?,
        title: j['title'] as String? ?? 'Producto',
        variantTitle: j['variant_title'] as String?,
        vendor: j['vendor'] as String?,
        productType: j['product_type'] as String?,
        price: (j['price'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        imageUrl: j['image_url'] as String?,
        isActive: j['is_active'] as bool? ?? true,
      );
}
