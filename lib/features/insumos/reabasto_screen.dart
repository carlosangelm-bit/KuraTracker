import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/inventory.dart';
import '../../services/data_repository.dart';
import '../../services/shopify_service.dart';

/// Reabasto sugerido (Insumos, Fase 5 premium): los artículos bajo su umbral se
/// juntan en una sugerencia de reorden. Para los de la tienda Kura+ se arma un
/// carrito de Shopify listo para pagar; los externos se listan aparte (con
/// proveedor) para comprarlos por fuera. La cantidad sugerida lleva la existencia
/// al doble del umbral (editable).
class ReabastoScreen extends ConsumerStatefulWidget {
  const ReabastoScreen({super.key});
  @override
  ConsumerState<ReabastoScreen> createState() => _ReabastoScreenState();
}

class _ReabastoScreenState extends ConsumerState<ReabastoScreen> {
  String? _siteId;
  final Map<String, int> _qty = {}; // itemId -> cantidad a reordenar (editable)
  bool _checkingOut = false;

  int _suggested(InventoryItem item, int onHand) {
    final target = (item.reorderThreshold ?? 0) * 2;
    final s = target - onHand;
    return s < 1 ? 1 : s;
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reabasto sugerido'),
        actions: const [UserMenuButton()],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final orgId = user?.organizationId;
          if (!repo.premiumInsumosFor(orgId)) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('El reabasto sugerido es una función premium.',
                        textAlign: TextAlign.center)));
          }
          final sites = repo
              .listSites(organizationId: orgId)
              .where((s) => s.isActive)
              .toList();
          if (sites.isEmpty) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Este centro no tiene sitios configurados.')));
          }
          _siteId ??= repo.primarySiteIdForProfile(user?.id) ?? sites.first.id;
          if (!sites.any((s) => s.id == _siteId)) _siteId = sites.first.id;

          final items = repo.listInventoryItems(organizationId: orgId, siteId: _siteId);
          final onHand = repo.inventoryOnHand(_siteId!);
          final low = items
              .where((it) =>
                  it.reorderThreshold != null &&
                  (onHand[it.id] ?? 0) <= it.reorderThreshold!)
              .toList();
          final storeLow =
              low.where((it) => !it.isExternal && it.shopifyVariantId != null).toList();
          final externalLow = low
              .where((it) => it.isExternal || it.shopifyVariantId == null)
              .toList();

          return Column(
            children: [
              if (sites.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _siteId,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final s in sites)
                              DropdownMenuItem(value: s.id, child: Text(s.name)),
                          ],
                          onChanged: (v) => setState(() => _siteId = v),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: low.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Todo con existencia suficiente.\n'
                            'No hay artículos bajo su umbral de reorden.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        children: [
                          if (storeLow.isNotEmpty) ...[
                            const Text('De tu tienda Kura+',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text('Ajusta la cantidad y arma el carrito de reorden.',
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 8),
                            for (final it in storeLow)
                              _StoreRow(
                                item: it,
                                onHand: onHand[it.id] ?? 0,
                                qty: _qty[it.id] ?? _suggested(it, onHand[it.id] ?? 0),
                                onQty: (q) => setState(() => _qty[it.id] = q),
                              ),
                            const SizedBox(height: 16),
                          ],
                          if (externalLow.isNotEmpty) ...[
                            const Text('Externos (comprar aparte)',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text('No están en tu tienda Kura+; cómpralos con su proveedor.',
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 8),
                            for (final it in externalLow)
                              _ExternalRow(
                                item: it,
                                onHand: onHand[it.id] ?? 0,
                                suggested: _suggested(it, onHand[it.id] ?? 0),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _buildCheckoutFab(repoAsync.valueOrNull, user?.organizationId),
    );
  }

  Widget? _buildCheckoutFab(DataRepository? repo, String? orgId) {
    if (repo == null || !repo.premiumInsumosFor(orgId) || _siteId == null) return null;
    final items = repo.listInventoryItems(organizationId: orgId, siteId: _siteId);
    final onHand = repo.inventoryOnHand(_siteId!);
    final storeLow = items
        .where((it) =>
            !it.isExternal &&
            it.shopifyVariantId != null &&
            it.reorderThreshold != null &&
            (onHand[it.id] ?? 0) <= it.reorderThreshold!)
        .toList();
    if (storeLow.isEmpty) return null;
    return FloatingActionButton.extended(
      onPressed: _checkingOut ? null : () => _checkout(repo, storeLow, onHand),
      icon: _checkingOut
          ? const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.shopping_cart_checkout),
      label: Text(_checkingOut
          ? 'Preparando…'
          : 'Reabastecer ${storeLow.length} en la tienda'),
    );
  }

  Future<void> _checkout(
      DataRepository repo, List<InventoryItem> storeLow, Map<String, int> onHand) async {
    final lines = <String, int>{};
    for (final it in storeLow) {
      final q = _qty[it.id] ?? _suggested(it, onHand[it.id] ?? 0);
      if (q > 0) lines[it.shopifyVariantId!] = q;
    }
    if (lines.isEmpty) return;
    setState(() => _checkingOut = true);
    try {
      final cart = await ref.read(shopifyServiceProvider).createCart(lines);
      final ok = await launchUrl(Uri.parse(cart.checkoutUrl),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
      if (!ok) throw ShopifyException('No se pudo abrir el checkout.');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }
}

class _StoreRow extends StatelessWidget {
  final InventoryItem item;
  final int onHand;
  final int qty;
  final ValueChanged<int> onQty;
  const _StoreRow({
    required this.item,
    required this.onHand,
    required this.qty,
    required this.onQty,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 40,
                height: 40,
                color: KuraColors.chipBg,
                child: item.imageUrl == null
                    ? const Icon(Icons.medical_services_outlined, size: 18)
                    : Image.network(item.imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image_not_supported_outlined, size: 18)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('Stock $onHand · umbral ${item.reorderThreshold}',
                      style: const TextStyle(fontSize: 11, color: KuraColors.warning)),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: qty > 1 ? () => onQty(qty - 1) : null,
                ),
                Text('$qty', style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () => onQty(qty + 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExternalRow extends StatelessWidget {
  final InventoryItem item;
  final int onHand;
  final int suggested;
  const _ExternalRow(
      {required this.item, required this.onHand, required this.suggested});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(item.name, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          [
            'Stock $onHand · umbral ${item.reorderThreshold}',
            if (item.supplier != null && item.supplier!.isNotEmpty)
              'Proveedor: ${item.supplier}',
          ].join(' · '),
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Sugerido', style: TextStyle(fontSize: 10, color: KuraColors.darkText)),
            Text('+$suggested',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
