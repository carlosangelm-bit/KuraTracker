import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/note_option_catalog.dart';
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

/// "Método" sintético para los insumos que el CENTRO agrega en su catálogo
/// (Configuración → Material utilizado). Definido en data_repository como
/// [kCenterMaterialsMethod] para que el mapeo y la nota apunten a lo mismo.
const _centerMaterialsMethod = kCenterMaterialsMethod;

/// Clave de un producto+presentación concretos (para checkbox/diff).
String _pickKey(String productId, String? variantId) =>
    '$productId|${variantId ?? ''}';

/// Mapeo insumo↔producto (Insumos, Fase 2 premium): el centro liga cada insumo
/// genérico de su protocolo a VARIOS productos concretos de su tienda Shopify
/// (distintas medidas/marcas/SKU); el especialista elige el específico al usarlo.
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
          final groups = repo.supplyMappingGroups(orgId);

          // Insumos que el CENTRO agrega en su catálogo (Configuración →
          // Material utilizado). Así, lo que el centro configure aparece aquí
          // para mapear, además de los insumos del protocolo incorporado.
          final centerMaterials = repo
              .listNoteOptions(NoteOptionField.materialsUsed, organizationId: orgId)
              .map((e) => e.label.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          _MethodGroup groupFor(String method, List<String> products) =>
              _MethodGroup(
                method: method,
                products: products,
                groups: groups,
                onEdit: (product) =>
                    _editProducts(context, repo, orgId, method, product),
                onRemove: (mappingId) async {
                  await repo.deleteSupplyMappingById(mappingId);
                  if (mounted) setState(() {});
                },
              );

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Liga cada insumo (de tu protocolo y de tu catálogo del centro) '
                  'a uno o varios productos de tu tienda. Puedes ligar distintas '
                  'medidas/marcas/SKU al mismo insumo; el especialista elige el '
                  'producto al asignarlo a un paciente. Se usa para costear y '
                  'sugerir reabasto. Puedes dejar sin asignar los que no manejes.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              if (centerMaterials.isNotEmpty)
                groupFor(_centerMaterialsMethod, centerMaterials),
              for (final method in _mappableMethods)
                groupFor(method,
                    TreatmentCatalog.methodToProducts[method] ?? const []),
            ],
          );
        },
      ),
    );
  }

  /// Abre el selector multi-checkbox para ligar/desligar varios productos a un
  /// insumo genérico, y aplica el diff contra lo ya ligado.
  Future<void> _editProducts(BuildContext context, DataRepository repo,
      String? orgId, String method, String product) async {
    if (orgId == null) return;
    final existing = repo.supplyMappingsFor(orgId, method, product);
    final result = await showModalBottomSheet<List<_Picked>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPickerSheet(
        method: method,
        genericProduct: product,
        existing: existing,
      ),
    );
    if (result == null) return; // canceló: sin cambios

    final existingByKey = {
      for (final m in existing)
        _pickKey(m.shopifyProductId, m.shopifyVariantId): m
    };
    final resultByKey = {
      for (final p in result) _pickKey(p.product.id, p.variant?.id): p
    };

    // Quitar los deseleccionados.
    for (final entry in existingByKey.entries) {
      if (!resultByKey.containsKey(entry.key)) {
        await repo.deleteSupplyMappingById(entry.value.id);
      }
    }
    // Agregar los nuevos.
    for (final entry in resultByKey.entries) {
      if (existingByKey.containsKey(entry.key)) continue;
      final picked = entry.value;
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
    }
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
  final Map<String, List<SupplyProductMapping>> groups;
  final void Function(String product) onEdit;
  final Future<void> Function(String mappingId) onRemove;
  const _MethodGroup({
    required this.method,
    required this.products,
    required this.groups,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final mapped = products
        .where((p) =>
            (groups[SupplyProductMapping.keyFor(method, p)] ?? const []).isNotEmpty)
        .length;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(method, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$mapped de ${products.length} con productos'),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            for (final p in products)
              _MapRow(
                genericProduct: p,
                mappings: groups[SupplyProductMapping.keyFor(method, p)] ??
                    const [],
                onEdit: () => onEdit(p),
                onRemove: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

class _MapRow extends StatelessWidget {
  final String genericProduct;
  final List<SupplyProductMapping> mappings;
  final VoidCallback onEdit;
  final Future<void> Function(String mappingId) onRemove;
  const _MapRow({
    required this.genericProduct,
    required this.mappings,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(genericProduct,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: onEdit,
                child: Text(mappings.isEmpty
                    ? 'Asignar'
                    : 'Editar (${mappings.length})'),
              ),
            ],
          ),
          if (mappings.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 4),
              child: Text('Sin asignar',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText)),
            )
          else
            ...mappings.map((m) => Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: 30,
                          height: 30,
                          color: KuraColors.chipBg,
                          child: m.imageUrl == null
                              ? const Icon(Icons.medical_services_outlined,
                                  size: 16)
                              : Image.network(m.imageUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.image_not_supported_outlined,
                                      size: 16)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _mappingLabel(m),
                          style: const TextStyle(
                              fontSize: 12, color: KuraColors.primary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar',
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onRemove(m.id),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  String _mappingLabel(SupplyProductMapping m) {
    final title = m.shopifyVariantTitle == null
        ? m.shopifyTitle
        : '${m.shopifyTitle} · ${m.shopifyVariantTitle}';
    if (m.priceAmount == null) return title;
    return '$title · \$${m.priceAmount!.toStringAsFixed(2)} ${m.priceCurrency ?? ''}';
  }
}

/// Un producto+presentación elegibles (nivel SKU cuando hay varias variantes).
class _Picked {
  final ShopifyProduct product;
  final ShopifyVariant? variant;
  const _Picked(this.product, this.variant);
  String get key => _pickKey(product.id, variant?.id);
}

/// Selector MULTI-checkbox de productos de la tienda (con buscador). Cada
/// producto con varias presentaciones se lista a nivel variante (SKU/medida)
/// para poder ligar las que apliquen. Devuelve la selección final; el llamador
/// aplica el diff contra lo ya ligado.
class _ProductPickerSheet extends ConsumerStatefulWidget {
  final String method;
  final String genericProduct;
  final List<SupplyProductMapping> existing;
  const _ProductPickerSheet({
    required this.method,
    required this.genericProduct,
    required this.existing,
  });
  @override
  ConsumerState<_ProductPickerSheet> createState() =>
      _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<_ProductPickerSheet> {
  String _search = '';
  // Selección actual: clave producto|variante → _Picked.
  final Map<String, _Picked> _selected = {};
  bool _initialized = false;

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

  /// Aplana un producto en sus entradas seleccionables: una por variante cuando
  /// hay varias (cada variante = un SKU/medida); una sola cuando hay 0/1.
  List<_Picked> _entriesFor(ShopifyProduct p) {
    final available = p.variants.where((v) => v.availableForSale).toList();
    final variants = available.isEmpty ? p.variants : available;
    if (variants.length <= 1) {
      return [_Picked(p, variants.isNotEmpty ? variants.first : null)];
    }
    return variants.map((v) => _Picked(p, v)).toList();
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
            Text('Productos para “${widget.genericProduct}”',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            const Text(
              'Marca todos los productos/presentaciones que apliquen.',
              style: TextStyle(fontSize: 12, color: KuraColors.darkText),
            ),
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
                  // Inicializa la selección desde lo ya ligado (una sola vez,
                  // cuando ya cargaron los productos para resolver variantes).
                  if (!_initialized) {
                    _initialized = true;
                    final byId = {for (final p in products) p.id: p};
                    for (final m in widget.existing) {
                      final p = byId[m.shopifyProductId];
                      if (p == null) continue;
                      ShopifyVariant? v;
                      if (m.shopifyVariantId != null) {
                        for (final vv in p.variants) {
                          if (vv.id == m.shopifyVariantId) {
                            v = vv;
                            break;
                          }
                        }
                      }
                      final picked = _Picked(p, v);
                      _selected[picked.key] = picked;
                    }
                  }

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
                  // Aplana a entradas seleccionables (nivel SKU).
                  final entries = <_Picked>[];
                  for (final p in list) {
                    entries.addAll(_entriesFor(p));
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _entryTile(entries[i]),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selected.values.toList()),
                    child: Text('Guardar (${_selected.length})'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryTile(_Picked e) {
    final p = e.product;
    final v = e.variant;
    final price = v?.price ?? p.fromPrice;
    final checked = _selected.containsKey(e.key);
    final title = v != null && p.variants.length > 1
        ? '${p.title} · ${v.title}'
        : p.title;
    return CheckboxListTile(
      value: checked,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      onChanged: (val) => setState(() {
        if (val == true) {
          _selected[e.key] = e;
        } else {
          _selected.remove(e.key);
        }
      }),
      secondary: ClipRRect(
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
      title: Text(title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        [
          if (p.vendor != null && p.vendor!.isNotEmpty) p.vendor,
          if (price != null) price.formatted,
        ].whereType<String>().join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
