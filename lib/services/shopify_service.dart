import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/shopify_config.dart';

/// Un producto de la tienda (Storefront API).
class ShopifyProduct {
  final String id;
  final String title;
  final String handle;
  final String? description;
  final String? imageUrl;
  final bool availableForSale;
  final String? productType;
  final String? vendor;
  final List<ShopifyVariant> variants;

  const ShopifyProduct({
    required this.id,
    required this.title,
    required this.handle,
    required this.availableForSale,
    required this.variants,
    this.description,
    this.imageUrl,
    this.productType,
    this.vendor,
  });

  /// Precio "desde" (menor precio de variante disponible).
  ShopifyMoney? get fromPrice {
    if (variants.isEmpty) return null;
    return variants.map((v) => v.price).reduce((a, b) => a.amount <= b.amount ? a : b);
  }

  factory ShopifyProduct.fromNode(Map<String, dynamic> n) {
    final img = n['featuredImage'] as Map<String, dynamic>?;
    final variantEdges = ((n['variants']?['edges']) as List?) ?? const [];
    return ShopifyProduct(
      id: n['id'] as String,
      title: n['title'] as String? ?? '',
      handle: n['handle'] as String? ?? '',
      description: n['description'] as String?,
      imageUrl: img?['url'] as String?,
      availableForSale: n['availableForSale'] as bool? ?? false,
      productType: (n['productType'] as String?)?.trim().isEmpty ?? true
          ? null
          : n['productType'] as String?,
      vendor: n['vendor'] as String?,
      variants: variantEdges
          .map((e) => ShopifyVariant.fromNode(e['node'] as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ShopifyVariant {
  final String id; // gid://shopify/ProductVariant/...
  final String title;
  final bool availableForSale;
  final ShopifyMoney price;

  const ShopifyVariant({
    required this.id,
    required this.title,
    required this.availableForSale,
    required this.price,
  });

  factory ShopifyVariant.fromNode(Map<String, dynamic> n) => ShopifyVariant(
        id: n['id'] as String,
        title: n['title'] as String? ?? '',
        availableForSale: n['availableForSale'] as bool? ?? false,
        price: ShopifyMoney.fromJson(n['price'] as Map<String, dynamic>),
      );
}

class ShopifyMoney {
  final double amount;
  final String currencyCode;
  const ShopifyMoney({required this.amount, required this.currencyCode});

  factory ShopifyMoney.fromJson(Map<String, dynamic> m) => ShopifyMoney(
        amount: double.tryParse('${m['amount']}') ?? 0,
        currencyCode: m['currencyCode'] as String? ?? 'MXN',
      );

  /// Formato simple "$1,234.00 MXN" (evita depender de datos de locale).
  String get formatted {
    final whole = amount.toStringAsFixed(2);
    final parts = whole.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '\$$buf.${parts[1]} $currencyCode';
  }
}

/// Resultado de crear un carrito: id + URL de checkout de Shopify.
class ShopifyCartResult {
  final String id;
  final String checkoutUrl;
  final int totalQuantity;
  final ShopifyMoney? total;
  const ShopifyCartResult({
    required this.id,
    required this.checkoutUrl,
    required this.totalQuantity,
    this.total,
  });
}

class ShopifyException implements Exception {
  final String message;
  ShopifyException(this.message);
  @override
  String toString() => 'ShopifyException: $message';
}

/// Cliente de la Storefront API de Shopify (GraphQL sobre HTTP). El token es
/// público-seguro; la API responde con CORS abierto, así que se llama directo
/// desde el cliente (no requiere Edge Function).
class ShopifyService {
  final http.Client _client;
  ShopifyService([http.Client? client]) : _client = client ?? http.Client();

  bool get isConfigured => ShopifyConfig.isConfigured;

  Future<Map<String, dynamic>> _query(String query,
      [Map<String, dynamic>? variables]) async {
    if (!ShopifyConfig.isConfigured) {
      throw ShopifyException('La tienda no está configurada (falta el token).');
    }
    final resp = await _client.post(
      ShopifyConfig.graphqlEndpoint,
      headers: {
        'Content-Type': 'application/json',
        'X-Shopify-Storefront-Access-Token': ShopifyConfig.storefrontToken,
      },
      body: jsonEncode({'query': query, if (variables != null) 'variables': variables}),
    );
    if (resp.statusCode != 200) {
      throw ShopifyException('Error de red (${resp.statusCode}).');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      throw ShopifyException('${errors.first['message'] ?? 'Error GraphQL'}');
    }
    return decoded['data'] as Map<String, dynamic>;
  }

  static const _productFields = '''
    id title handle description availableForSale productType vendor
    featuredImage { url }
    variants(first: 20) {
      edges { node { id title availableForSale price { amount currencyCode } } }
    }
  ''';

  /// Lista productos de la tienda. `search` filtra por texto (title/tipo/tag).
  Future<List<ShopifyProduct>> fetchProducts({String? search, int first = 50}) async {
    final data = await _query('''
      query Products(\$first: Int!, \$query: String) {
        products(first: \$first, query: \$query, sortKey: TITLE) {
          edges { node { $_productFields } }
        }
      }
    ''', {'first': first, if (search != null && search.isNotEmpty) 'query': search});
    final edges = (data['products']?['edges'] as List?) ?? const [];
    return edges
        .map((e) => ShopifyProduct.fromNode(e['node'] as Map<String, dynamic>))
        .toList();
  }

  /// Crea un carrito con las líneas dadas y devuelve la URL de checkout.
  Future<ShopifyCartResult> createCart(Map<String, int> linesByVariantId) async {
    final lines = linesByVariantId.entries
        .where((e) => e.value > 0)
        .map((e) => {'merchandiseId': e.key, 'quantity': e.value})
        .toList();
    if (lines.isEmpty) {
      throw ShopifyException('El carrito está vacío.');
    }
    final data = await _query('''
      mutation CartCreate(\$lines: [CartLineInput!]!) {
        cartCreate(input: {lines: \$lines}) {
          cart {
            id checkoutUrl totalQuantity
            cost { totalAmount { amount currencyCode } }
          }
          userErrors { field message }
        }
      }
    ''', {'lines': lines});
    final result = data['cartCreate'] as Map<String, dynamic>?;
    final userErrors = (result?['userErrors'] as List?) ?? const [];
    if (userErrors.isNotEmpty) {
      throw ShopifyException('${userErrors.first['message'] ?? 'No se pudo crear el carrito'}');
    }
    final cart = result?['cart'] as Map<String, dynamic>?;
    if (cart == null) throw ShopifyException('No se pudo crear el carrito.');
    final cost = cart['cost']?['totalAmount'] as Map<String, dynamic>?;
    return ShopifyCartResult(
      id: cart['id'] as String,
      checkoutUrl: cart['checkoutUrl'] as String,
      totalQuantity: (cart['totalQuantity'] as num?)?.toInt() ?? 0,
      total: cost == null ? null : ShopifyMoney.fromJson(cost),
    );
  }
}

final shopifyServiceProvider = Provider<ShopifyService>((ref) {
  final service = ShopifyService();
  ref.onDispose(service._client.close);
  return service;
});

/// Catálogo de productos (cacheado por la vida del provider).
final shopifyProductsProvider =
    FutureProvider.autoDispose<List<ShopifyProduct>>((ref) async {
  return ref.watch(shopifyServiceProvider).fetchProducts();
});
