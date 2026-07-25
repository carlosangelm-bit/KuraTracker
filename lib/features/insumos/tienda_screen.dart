import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/kura_theme.dart';
import '../../services/shopify_service.dart';
import 'cart_provider.dart';

/// Tienda del módulo de Insumos: catálogo de productos de heridas (Shopify
/// Storefront API) + carrito → checkout alojado de Shopify. Parte BASE del
/// módulo (no requiere licencia premium).
class TiendaScreen extends ConsumerWidget {
  const TiendaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(shopifyServiceProvider);
    final count = ref.watch(cartCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tienda de insumos'),
        actions: [
          IconButton(
            tooltip: 'Carrito',
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            onPressed: () => _openCart(context, ref),
          ),
        ],
      ),
      body: !service.isConfigured
          ? const _NotConfigured()
          : _ProductsBody(),
    );
  }

  static void _openCart(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CartSheet(),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'La tienda no está configurada en este entorno.\n'
            'Falta el Storefront access token de Shopify.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _ProductsBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(shopifyProductsProvider);
    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: KuraColors.danger),
              const SizedBox(height: 8),
              Text('No se pudo cargar el catálogo.\n$e',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(shopifyProductsProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
      data: (products) {
        if (products.isEmpty) {
          return const Center(child: Text('No hay productos disponibles.'));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(shopifyProductsProvider),
          child: LayoutBuilder(
            builder: (context, c) {
              final cols = (c.maxWidth / 260).floor().clamp(1, 5);
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.66,
                ),
                itemCount: products.length,
                itemBuilder: (_, i) => _ProductCard(product: products[i]),
              );
            },
          ),
        );
      },
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final ShopifyProduct product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = product.fromPrice;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              color: KuraColors.chipBg,
              child: product.imageUrl == null
                  ? const Icon(Icons.medical_services_outlined, size: 40)
                  : Image.network(
                      product.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  price == null
                      ? '—'
                      : (product.variants.length > 1
                          ? 'Desde ${price.formatted}'
                          : price.formatted),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: KuraColors.primary),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        visualDensity: VisualDensity.compact),
                    onPressed: product.availableForSale
                        ? () => _addToCart(context, ref)
                        : null,
                    child: Text(product.availableForSale ? 'Agregar' : 'Agotado',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addToCart(BuildContext context, WidgetRef ref) {
    final available = product.variants.where((v) => v.availableForSale).toList();
    // Una sola variante disponible → agregar directo.
    if (available.length <= 1) {
      final v = available.isNotEmpty ? available.first : product.variants.first;
      ref.read(cartProvider.notifier).add(product, v);
      _snack(context, 'Agregado: ${product.title}');
      return;
    }
    // Varias variantes → hoja de selección.
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => _VariantSheet(product: product),
    );
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}

class _VariantSheet extends ConsumerStatefulWidget {
  final ShopifyProduct product;
  const _VariantSheet({required this.product});
  @override
  ConsumerState<_VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends ConsumerState<_VariantSheet> {
  String? _variantId;

  @override
  Widget build(BuildContext context) {
    final variants = widget.product.variants;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.product.title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('Presentación', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in variants)
                ChoiceChip(
                  label: Text('${v.title} · ${v.price.formatted}',
                      style: const TextStyle(fontSize: 12)),
                  selected: _variantId == v.id,
                  onSelected: v.availableForSale
                      ? (_) => setState(() => _variantId = v.id)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _variantId == null
                  ? null
                  : () {
                      final v = variants.firstWhere((x) => x.id == _variantId);
                      ref.read(cartProvider.notifier).add(widget.product, v);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Agregado: ${widget.product.title}')),
                      );
                    },
              child: const Text('Agregar al carrito'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSheet extends ConsumerStatefulWidget {
  const _CartSheet();
  @override
  ConsumerState<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<_CartSheet> {
  bool _checkingOut = false;

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final currency =
        lines.isEmpty ? 'MXN' : lines.first.variant.price.currencyCode;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Carrito',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                if (lines.isNotEmpty)
                  TextButton(
                    onPressed: () => ref.read(cartProvider.notifier).clear(),
                    child: const Text('Vaciar'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Tu carrito está vacío.')),
              )
            else ...[
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) => _CartLineTile(line: lines[i]),
                ),
              ),
              const Divider(),
              Row(
                children: [
                  const Expanded(
                    child: Text('Total',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    ShopifyMoney(amount: total, currencyCode: currency).formatted,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _checkingOut
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lock_outline, size: 18),
                  label: Text(_checkingOut ? 'Preparando…' : 'Ir a pagar'),
                  onPressed: _checkingOut ? null : _checkout,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'El pago se completa de forma segura en la tienda Shopify.',
                style: TextStyle(fontSize: 11, color: KuraColors.darkText),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _checkout() async {
    setState(() => _checkingOut = true);
    try {
      final service = ref.read(shopifyServiceProvider);
      final lines = ref.read(cartProvider.notifier).linesByVariantId;
      final cart = await service.createCart(lines);
      final ok = await launchUrl(
        Uri.parse(cart.checkoutUrl),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!ok) throw ShopifyException('No se pudo abrir el checkout.');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _checkingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}

class _CartLineTile extends ConsumerWidget {
  final CartLine line;
  const _CartLineTile({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 44,
            height: 44,
            color: KuraColors.chipBg,
            child: line.product.imageUrl == null
                ? const Icon(Icons.medical_services_outlined, size: 20)
                : Image.network(line.product.imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined, size: 20)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.product.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              if (line.variant.title.isNotEmpty &&
                  line.variant.title.toLowerCase() != 'default title')
                Text(line.variant.title,
                    style: const TextStyle(fontSize: 11, color: KuraColors.darkText)),
              Text(line.variant.price.formatted,
                  style: const TextStyle(fontSize: 12, color: KuraColors.primary)),
            ],
          ),
        ),
        _QtyStepper(
          quantity: line.quantity,
          onChanged: (q) => notifier.setQuantity(line.variant.id, q),
        ),
      ],
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;
  const _QtyStepper({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: () => onChanged(quantity - 1),
        ),
        Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}
