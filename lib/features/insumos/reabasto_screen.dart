import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/inventory.dart';
import '../../models/supply_order.dart';
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
          // Espejo Shopify unifica el inventario por centro (ver inventario_screen).
          final centerMode = repo.inventoryScopeFor(orgId) == 'center' ||
              repo.shopifyMirrorFor(orgId);
          if (centerMode) {
            _siteId = sites.first.id;
          } else {
            _siteId ??= repo.primarySiteIdForProfile(user?.id) ?? sites.first.id;
            if (!sites.any((s) => s.id == _siteId)) _siteId = sites.first.id;
          }

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
          final openOrders = orgId == null
              ? <SupplyOrder>[]
              : repo.listSupplyOrders(orgId, openOnly: true);

          final purchases = repo.listRecentPurchases(_siteId!, limit: 15);
          final nameById = {for (final it in items) it.id: it.name};

          return Column(
            children: [
              if (!centerMode && sites.length > 1)
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    if (openOrders.isNotEmpty) ...[
                      const Text('Pedidos por recibir',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Cierra la recepción contra el pedido que armaste.',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      for (final o in openOrders)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Pedido ${o.createdAt.day}/${o.createdAt.month}/${o.createdAt.year}'
                                        '${o.status == 'parcial' ? ' · parcial' : ''}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: () => _receiveOrder(repo, o),
                                      child: const Text('Recibir'),
                                    ),
                                  ],
                                ),
                                for (final it in o.items)
                                  Text(
                                      '· ${it.name}: ${it.quantityReceived}/${it.quantityOrdered}',
                                      style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      const Divider(height: 24),
                    ],
                    if (low.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Todo con existencia suficiente.\n'
                          'No hay artículos bajo su umbral de reorden.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (storeLow.isNotEmpty) ...[
                      const Text('De tu tienda Kura+',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Ajusta la cantidad y arma el carrito; al recibir, confirma la recepción.',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      for (final it in storeLow)
                        _StoreRow(
                          item: it,
                          onHand: onHand[it.id] ?? 0,
                          qty: _qty[it.id] ?? _suggested(it, onHand[it.id] ?? 0),
                          onQty: (q) => setState(() => _qty[it.id] = q),
                          onReceive: () => _recepcion(repo, it, _qty[it.id] ?? _suggested(it, onHand[it.id] ?? 0)),
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
                          onReceive: () => _recepcion(repo, it, _suggested(it, onHand[it.id] ?? 0)),
                        ),
                      const SizedBox(height: 16),
                    ],
                    if (purchases.isNotEmpty) ...[
                      const Text('Compras recientes',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      for (final m in purchases)
                        _PurchaseRow(
                          name: nameById[m.inventoryItemId] ?? 'Artículo',
                          movement: m,
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

  /// Confirmar recepción: registra la entrada (compra) al inventario cuando
  /// llega el pedido (Shopify no lo actualiza solo). Cantidad editable.
  Future<void> _recepcion(DataRepository repo, InventoryItem item, int suggested) async {
    final ctrl = TextEditingController(text: '$suggested');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar recepción'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Cantidad recibida'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true) return;
    final qty = int.tryParse(ctrl.text.trim()) ?? 0;
    if (qty <= 0) return;
    await repo.addInventoryMovement(
      item: item,
      delta: qty,
      reason: InventoryReason.compra,
      unitCost: item.unitCost,
      note: 'Recepción de compra',
      createdBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recepción registrada: +$qty ${item.name}')),
      );
    }
  }

  /// Cierra la recepción de un pedido: por cada item, la cantidad recibida
  /// (prellenada con lo pendiente). Registra la entrada y actualiza el estado.
  Future<void> _receiveOrder(DataRepository repo, SupplyOrder order) async {
    final pend = order.items.where((i) => i.pending > 0).toList();
    if (pend.isEmpty) return;
    final ctrls = {
      for (final it in pend) it.id: TextEditingController(text: '${it.pending}'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recibir pedido'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final it in pend)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(it.name,
                              style: const TextStyle(fontSize: 13))),
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: ctrls[it.id],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              isDense: true, hintText: '${it.pending}'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    final received = <String, int>{
      for (final e in ctrls.entries) e.key: int.tryParse(e.value.text.trim()) ?? 0,
    };
    await repo.receiveSupplyOrder(order.id, received,
        createdBy: ref.read(sessionProvider).user?.id);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recepción registrada contra el pedido.')));
    }
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
      // Registra el PEDIDO con lo solicitado; la recepción cerrará contra él
      // (0095), en vez de capturar una entrada "de la nada".
      final orgId = ref.read(sessionProvider).user?.organizationId;
      if (orgId != null) {
        await repo.createSupplyOrder(
          organizationId: orgId,
          siteId: _siteId,
          lines: [
            for (final it in storeLow)
              if ((_qty[it.id] ?? _suggested(it, onHand[it.id] ?? 0)) > 0)
                (
                  itemId: it.id,
                  name: it.name,
                  qty: _qty[it.id] ?? _suggested(it, onHand[it.id] ?? 0)
                ),
          ],
          createdBy: ref.read(sessionProvider).user?.id,
        );
      }
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
  final VoidCallback onReceive;
  const _StoreRow({
    required this.item,
    required this.onHand,
    required this.qty,
    required this.onQty,
    required this.onReceive,
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
                IconButton(
                  tooltip: 'Confirmar recepción',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.inventory_outlined, size: 18),
                  onPressed: onReceive,
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
  final VoidCallback onReceive;
  const _ExternalRow(
      {required this.item,
      required this.onHand,
      required this.suggested,
      required this.onReceive});

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Sugerido',
                    style: TextStyle(fontSize: 10, color: KuraColors.darkText)),
                Text('+$suggested',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            IconButton(
              tooltip: 'Confirmar recepción',
              icon: const Icon(Icons.inventory_outlined, size: 18),
              onPressed: onReceive,
            ),
          ],
        ),
      ),
    );
  }
}

/// Renglón del historial de compras (entradas reason=compra).
class _PurchaseRow extends StatelessWidget {
  final String name;
  final InventoryMovement movement;
  const _PurchaseRow({required this.name, required this.movement});

  @override
  Widget build(BuildContext context) {
    final d = movement.createdAt;
    final date = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined, size: 18, color: KuraColors.success),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          Text('+${movement.delta}  ·  $date',
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
