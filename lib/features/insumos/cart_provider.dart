import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/shopify_service.dart';

/// Una línea del carrito (una variante + cantidad).
class CartLine {
  final ShopifyProduct product;
  final ShopifyVariant variant;
  final int quantity;
  const CartLine({
    required this.product,
    required this.variant,
    required this.quantity,
  });

  double get lineTotal => variant.price.amount * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
        product: product,
        variant: variant,
        quantity: quantity ?? this.quantity,
      );
}

/// Carrito en memoria (se vacía al recargar). El pago real ocurre en el checkout
/// de Shopify: al pagar se crea un cart en Shopify con estas líneas.
class CartNotifier extends StateNotifier<List<CartLine>> {
  CartNotifier() : super(const []);

  void add(ShopifyProduct product, ShopifyVariant variant, {int quantity = 1}) {
    final idx = state.indexWhere((l) => l.variant.id == variant.id);
    if (idx >= 0) {
      final updated = [...state];
      updated[idx] = updated[idx].copyWith(quantity: updated[idx].quantity + quantity);
      state = updated;
    } else {
      state = [...state, CartLine(product: product, variant: variant, quantity: quantity)];
    }
  }

  void setQuantity(String variantId, int quantity) {
    if (quantity <= 0) {
      remove(variantId);
      return;
    }
    state = [
      for (final l in state)
        if (l.variant.id == variantId) l.copyWith(quantity: quantity) else l,
    ];
  }

  void remove(String variantId) =>
      state = state.where((l) => l.variant.id != variantId).toList();

  void clear() => state = const [];

  Map<String, int> get linesByVariantId =>
      {for (final l in state) l.variant.id: l.quantity};
}

final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartLine>>((ref) => CartNotifier());

/// Nº total de piezas en el carrito.
final cartCountProvider = Provider<int>((ref) =>
    ref.watch(cartProvider).fold<int>(0, (a, l) => a + l.quantity));

/// Total del carrito (asume una sola moneda; la tienda es MXN).
final cartTotalProvider = Provider<double>((ref) =>
    ref.watch(cartProvider).fold<double>(0, (a, l) => a + l.lineTotal));
