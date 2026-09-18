import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../models/product_catalog_item.dart';
import '../../services/data_repository.dart';

/// Abre el selector de producto de la tienda Kura+ (con buscador). LEE DEL CATÁLOGO
/// LOCAL YA SINCRONIZADO (`product_catalog`), NO consulta Shopify en vivo: dar de alta
/// un insumo NO debe depender de que la Storefront API esté arriba y autorizada en ese
/// instante (antes reventaba con un `ShopifyException: Error de red (401)` crudo en cara
/// del usuario). La sincronización del catálogo con Shopify es un proceso APARTE
/// (Insumos → Tienda / mapeo). Devuelve el producto elegido, o null si se cancela.
Future<ProductCatalogItem?> showShopifyProductPicker(
  BuildContext context,
  DataRepository repo, {
  String title = 'Elegir producto de la tienda',
}) {
  return showModalBottomSheet<ProductCatalogItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ProductPickerSheet(title: title, repo: repo),
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

class _ProductPickerSheet extends StatefulWidget {
  final String title;
  final DataRepository repo;
  const _ProductPickerSheet({required this.title, required this.repo});
  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final catalog = widget.repo.listProductCatalog();
    final q = _fold(_search);
    final list = q.isEmpty
        ? catalog
        : catalog
            .where((p) => _fold(
                    '${p.displayName} ${p.vendor ?? ''} ${p.productType ?? ''} ${p.sku ?? ''}')
                .contains(q))
            .toList();
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
              child: catalog.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: Text(
                              'El catálogo de la tienda todavía no está disponible. '
                              'Sincronízalo desde Insumos → Tienda y vuelve a intentar.',
                              textAlign: TextAlign.center)))
                  : list.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Sin resultados.')))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _tile(list[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ProductCatalogItem p) {
    final priceStr = p.price == null
        ? null
        : '\$${p.price!.toStringAsFixed(2)} ${p.currency ?? 'MXN'}';
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
      title: Text(p.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        [
          if (p.vendor != null && p.vendor!.isNotEmpty) p.vendor,
          if (priceStr != null) priceStr,
        ].whereType<String>().join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => Navigator.of(context).pop(p),
    );
  }
}
