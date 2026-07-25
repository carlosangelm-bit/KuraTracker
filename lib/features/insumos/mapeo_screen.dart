import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/supply_product_mapping.dart';
import '../../services/data_repository.dart';
import '../../services/shopify_service.dart';
import '../treatment/treatment_catalog.dart';

/// Métodos del protocolo cuyos insumos son CONSUMIBLES comprables (se mapean a
/// productos de la tienda). Se excluyen métodos que son procedimientos
/// (desbridamiento, descarga, manejo quirúrgico/traumático, educación…).
const _mappableMethods = [
  'Limpieza de la herida',
  'Relleno de cavidad',
  'Apósito',
  'Protección de la piel',
  'Antisépticos',
  'Tratamiento para la infección',
  'Terapia compresiva',
];

/// Mapeo insumo↔producto (Insumos, Fase 2 premium): el centro liga cada insumo
/// genérico de su protocolo a un producto concreto de su tienda Shopify.
class MapeoScreen extends ConsumerStatefulWidget {
  const MapeoScreen({super.key});
  @override
  ConsumerState<MapeoScreen> createState() => _MapeoScreenState();
}

class _MapeoScreenState extends ConsumerState<MapeoScreen> {
  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapeo de insumos'),
        actions: const [UserMenuButton()],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final orgId = user?.organizationId;
          if (!repo.premiumInsumosFor(orgId)) {
            return const _PremiumLocked();
          }
          final index = repo.supplyMappingIndex(orgId);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Liga cada insumo de tu protocolo a un producto de tu tienda. '
                  'Se usa para asignar insumos a pacientes, costear y sugerir '
                  'reabasto. Puedes dejar sin asignar los que no manejes.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              for (final method in _mappableMethods)
                _MethodGroup(
                  method: method,
                  products: TreatmentCatalog.methodToProducts[method] ?? const [],
                  index: index,
                  onEdit: (product) => _assign(context, repo, orgId, method, product),
                  onClear: (product) async {
                    await repo.deleteSupplyMapping(
                      organizationId: orgId!,
                      method: method,
                      genericProduct: product,
                    );
                    if (mounted) setState(() {});
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _assign(BuildContext context, DataRepository repo, String? orgId,
      String method, String product) async {
    final picked = await showModalBottomSheet<_Picked>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPickerSheet(method: method, genericProduct: product),
    );
    if (picked == null || orgId == null) return;
    final price = picked.variant?.price ?? picked.product.fromPrice;
    await repo.setSupplyMapping(
      organizationId: orgId,
      method: method,
      genericProduct: product,
      shopifyProductId: picked.product.id,
      shopifyTitle: picked.product.title,
      shopifyVariantId: picked.variant?.id,
      shopifyVariantTitle: picked.variant?.title,
      shopifyHandle: picked.product.handle,
      imageUrl: picked.product.imageUrl,
      priceAmount: price?.amount,
      priceCurrency: price?.currencyCode,
      updatedBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) setState(() {});
  }
}

class _PremiumLocked extends StatelessWidget {
  const _PremiumLocked();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_outlined, color: KuraColors.warning),
              SizedBox(height: 8),
              Text(
                'El mapeo de insumos es una función premium.\n'
                'Solicita la licencia a tu administrador de plataforma.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _MethodGroup extends StatelessWidget {
  final String method;
  final List<String> products;
  final Map<String, SupplyProductMapping> index;
  final void Function(String product) onEdit;
  final Future<void> Function(String product) onClear;
  const _MethodGroup({
    required this.method,
    required this.products,
    required this.index,
    required this.onEdit,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final mapped = products
        .where((p) => index.containsKey(SupplyProductMapping.keyFor(method, p)))
        .length;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(method, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$mapped de ${products.length} asignados'),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            for (final p in products)
              _MapRow(
                genericProduct: p,
                mapping: index[SupplyProductMapping.keyFor(method, p)],
                onEdit: () => onEdit(p),
                onClear: () => onClear(p),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapRow extends StatelessWidget {
  final String genericProduct;
  final SupplyProductMapping? mapping;
  final VoidCallback onEdit;
  final Future<void> Function() onClear;
  const _MapRow({
    required this.genericProduct,
    required this.mapping,
    required this.onEdit,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final m = mapping;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(genericProduct,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (m == null)
                  const Text('Sin asignar',
                      style: TextStyle(fontSize: 12, color: KuraColors.darkText))
                else
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: 30,
                          height: 30,
                          color: KuraColors.chipBg,
                          child: m.imageUrl == null
                              ? const Icon(Icons.medical_services_outlined, size: 16)
                              : Image.network(m.imageUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.image_not_supported_outlined,
                                          size: 16)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m.priceAmount == null
                              ? m.shopifyTitle
                              : '${m.shopifyTitle} · \$${m.priceAmount!.toStringAsFixed(2)} ${m.priceCurrency ?? ''}',
                          style: const TextStyle(
                              fontSize: 12, color: KuraColors.primary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (m != null)
            IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClear,
            ),
          TextButton(
            onPressed: onEdit,
            child: Text(m == null ? 'Asignar' : 'Cambiar'),
          ),
        ],
      ),
    );
  }
}

/// Resultado del selector: producto + variante opcional.
class _Picked {
  final ShopifyProduct product;
  final ShopifyVariant? variant;
  const _Picked(this.product, this.variant);
}

/// Selector de producto de la tienda (con buscador). Al elegir un producto con
/// varias variantes, pide elegir la presentación.
class _ProductPickerSheet extends ConsumerStatefulWidget {
  final String method;
  final String genericProduct;
  const _ProductPickerSheet(
      {required this.method, required this.genericProduct});
  @override
  ConsumerState<_ProductPickerSheet> createState() =>
      _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<_ProductPickerSheet> {
  String _search = '';

  static String _fold(String s) {
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
            Text('Asignar producto a “${widget.genericProduct}”',
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
                loading: () =>
                    const Center(child: Padding(
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
                    itemBuilder: (_, i) => _pickerTile(list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerTile(ShopifyProduct p) {
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
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        [
          if (p.vendor != null && p.vendor!.isNotEmpty) p.vendor,
          if (price != null)
            (p.variants.length > 1
                ? 'Desde ${price.formatted}'
                : price.formatted),
        ].whereType<String>().join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => _choose(p),
    );
  }

  Future<void> _choose(ShopifyProduct p) async {
    final available = p.variants.where((v) => v.availableForSale).toList();
    final variants = available.isEmpty ? p.variants : available;
    // Una sola presentación → asignar directo.
    if (variants.length <= 1) {
      Navigator.of(context).pop(
          _Picked(p, variants.isNotEmpty ? variants.first : null));
      return;
    }
    // Varias presentaciones → elegir una (o el producto en general).
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
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('Cualquier presentación (nivel producto)'),
              onTap: () => Navigator.of(context).pop(null),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(_Picked(p, chosen));
  }
}
