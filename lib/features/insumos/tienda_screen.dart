import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/kura_theme.dart';
import '../../services/shopify_service.dart';
import 'cart_provider.dart';

/// Tienda del módulo de Insumos: catálogo de productos de heridas (Shopify
/// Storefront API) + carrito → checkout alojado de Shopify. Parte BASE del
/// módulo (no requiere licencia premium).
class TiendaScreen extends ConsumerStatefulWidget {
  const TiendaScreen({super.key});

  @override
  ConsumerState<TiendaScreen> createState() => _TiendaScreenState();
}

class _TiendaScreenState extends ConsumerState<TiendaScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _category; // clave normalizada (minúsculas sin acento)
  String? _brand; // vendor exacto

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Normaliza a minúsculas sin acentos (para comparar/buscar sin depender de
  /// mayúsculas ni tildes; la data de la tienda es inconsistente).
  static String fold(String s) {
    s = s.toLowerCase().trim();
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const to = 'aaaaaeeeeiiiiooooouuuun';
    final b = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final i = from.indexOf(c);
      b.write(i >= 0 ? to[i] : c);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: _openCart,
          ),
        ],
      ),
      body: !service.isConfigured ? const _NotConfigured() : _buildBody(),
    );
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CartSheet(),
    );
  }

  Widget _buildBody() {
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
        // Facetas: categorías (productType, deduplicadas por clave normalizada,
        // conservando una etiqueta legible) y marcas (vendor, ya limpio).
        final catLabels = <String, String>{};
        for (final p in products) {
          final pt = (p.productType ?? '').trim();
          if (pt.isEmpty) continue;
          catLabels.putIfAbsent(fold(pt), () => pt);
        }
        final categories = catLabels.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final brands = <String>{
          for (final p in products)
            if ((p.vendor ?? '').trim().isNotEmpty) p.vendor!.trim()
        }.toList()
          ..sort();

        // Selecciones inválidas (tras recarga) → limpiar.
        if (_category != null && !catLabels.containsKey(_category)) _category = null;
        if (_brand != null && !brands.contains(_brand)) _brand = null;

        final q = fold(_search);
        final filtered = products.where((p) {
          if (_category != null && fold(p.productType ?? '') != _category) {
            return false;
          }
          if (_brand != null && (p.vendor ?? '').trim() != _brand) return false;
          if (q.isNotEmpty) {
            final hay = fold('${p.title} ${p.vendor ?? ''} ${p.productType ?? ''}');
            if (!hay.contains(q)) return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            _FilterBar(
              searchController: _searchCtrl,
              categories: categories,
              brands: brands,
              category: _category,
              brand: _brand,
              resultCount: filtered.length,
              totalCount: products.length,
              onSearch: (v) => setState(() => _search = v),
              onCategory: (v) => setState(() => _category = v),
              onBrand: (v) => setState(() => _brand = v),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Ningún producto coincide con los filtros.',
                            textAlign: TextAlign.center),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(shopifyProductsProvider),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final cols = (c.maxWidth / 260).floor().clamp(1, 5);
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.66,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) =>
                                _ProductCard(product: filtered[i]),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
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

/// Barra de filtros: buscador + categoría + marca + conteo de resultados.
class _FilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final List<MapEntry<String, String>> categories; // clave -> etiqueta
  final List<String> brands;
  final String? category;
  final String? brand;
  final int resultCount;
  final int totalCount;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onBrand;

  const _FilterBar({
    required this.searchController,
    required this.categories,
    required this.brands,
    required this.category,
    required this.brand,
    required this.resultCount,
    required this.totalCount,
    required this.onSearch,
    required this.onCategory,
    required this.onBrand,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onSearch,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar producto…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        searchController.clear();
                        onSearch('');
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FilterDropdown<String>(
                icon: Icons.category_outlined,
                hint: 'Categoría',
                value: category,
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c.key, child: Text(c.value)),
                ],
                onChanged: onCategory,
              ),
              _FilterDropdown<String>(
                icon: Icons.sell_outlined,
                hint: 'Marca',
                value: brand,
                items: [
                  for (final b in brands)
                    DropdownMenuItem(value: b, child: Text(b)),
                ],
                onChanged: onBrand,
              ),
              if (category != null || brand != null || searchController.text.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Limpiar'),
                  onPressed: () {
                    searchController.clear();
                    onSearch('');
                    onCategory(null);
                    onBrand(null);
                  },
                ),
              Text('$resultCount de $totalCount',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dropdown compacto con opción "Todos" (null) al inicio.
class _FilterDropdown<T> extends StatelessWidget {
  final IconData icon;
  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _FilterDropdown({
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: KuraColors.chipBg),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: KuraColors.darkText),
          const SizedBox(width: 6),
          DropdownButton<T?>(
            value: value,
            hint: Text(hint, style: const TextStyle(fontSize: 13)),
            underline: const SizedBox.shrink(),
            isDense: true,
            items: [
              DropdownMenuItem<T?>(value: null, child: Text('$hint: todas')),
              ...items,
            ],
            onChanged: onChanged,
          ),
        ],
      ),
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
