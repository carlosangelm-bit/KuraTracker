import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../services/shopify_service.dart';

/// Resultado del selector de producto de la tienda: producto + variante opcional.
class PickedShopifyProduct {
  final ShopifyProduct product;
  final ShopifyVariant? variant;
  const PickedShopifyProduct(this.product, this.variant);
}

/// Abre el selector de producto de la tienda (con buscador). Devuelve el
/// producto elegido (y la presentación si tiene varias), o null si se cancela.
Future<PickedShopifyProduct?> showShopifyProductPicker(BuildContext context,
    {String title = 'Elegir producto de la tienda'}) {
  return showModalBottomSheet<PickedShopifyProduct>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ProductPickerSheet(title: title),
  );
}

String _fold(String s) {
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

class _ProductPickerSheet extends ConsumerStatefulWidget {
  final String title;
  const _ProductPickerSheet({required this.title});
  @override
  ConsumerState<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<_ProductPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(shopifyProductsProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Buscar en la tienda…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: productsAsync.when(
                loading: () => const Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator())),
                error: (e, st) => Padding(
                    padding: const EdgeInsets.all(16), child: Text('Error: $e')),
                data: (products) {
                  final q = _fold(_search);
                  final list = q.isEmpty
                      ? products
                      : products
                          .where((p) => _fold(
                                  '${p.title} ${p.vendor ?? ''} ${p.productType ?? ''}')
                              .contains(q))
                          .toList();
                  if (list.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Sin resultados.')));
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _tile(list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ShopifyProduct p) {
    final price = p.fromPrice;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 40,
          height: 40,
          color: KuraColors.chipBg,
          child: p.imageUrl == null
              ? const Icon(Icons.medical_services_outlined, size: 18)
              : Image.network(p.imageUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image_not_supported_outlined, size: 18)),
        ),
      ),
      title: Text(p.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        [
          if (p.vendor != null && p.vendor!.isNotEmpty) p.vendor,
          if (price != null)
            (p.variants.length > 1 ? 'Desde ${price.formatted}' : price.formatted),
        ].whereType<String>().join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => _choose(p),
    );
  }

  Future<void> _choose(ShopifyProduct p) async {
    final available = p.variants.where((v) => v.availableForSale).toList();
    final variants = available.isEmpty ? p.variants : available;
    if (variants.length <= 1) {
      Navigator.of(context).pop(
          PickedShopifyProduct(p, variants.isNotEmpty ? variants.first : null));
      return;
    }
    final chosen = await showModalBottomSheet<ShopifyVariant?>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Presentación de ${p.title}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final v in variants)
              ListTile(
                title: Text(v.title),
                trailing: Text(v.price.formatted),
                onTap: () => Navigator.of(context).pop(v),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (chosen == null) return; // canceló la elección de variante
    Navigator.of(context).pop(PickedShopifyProduct(p, chosen));
  }
}
