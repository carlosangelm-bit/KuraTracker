import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/app_user.dart';
import '../../models/inventory.dart';
import '../../services/csv_download.dart';
import '../../services/data_repository.dart';
import 'product_picker.dart';

String _money(double? v, [String? cur]) =>
    v == null ? '—' : '\$${v.toStringAsFixed(2)} ${cur ?? 'MXN'}';

/// Inventario de insumos por SITIO (Insumos, Fase 3 premium): existencias de
/// productos de la tienda Kura+ y externos, con bitácora de movimientos.
class InventarioScreen extends ConsumerStatefulWidget {
  const InventarioScreen({super.key});
  @override
  ConsumerState<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends ConsumerState<InventarioScreen> {
  String? _siteId;
  bool _importing = false;

  // Encabezado del CSV de carga masiva de inventario.
  static const _csvHeader = [
    'sku',
    'nombre',
    'proveedor',
    'costo',
    'precio',
    'moneda',
    'cantidad',
    'shopify_product_id',
    'shopify_variant_id',
  ];

  /// Descarga un CSV con el catálogo global completo (para que el centro ajuste
  /// costo/cantidad) + una fila guía. Se puede agregar productos nuevos con
  /// filas cuyo shopify_product_id quede vacío.
  Future<void> _downloadCsv(DataRepository repo, String? orgId) async {
    final catalog = repo.listProductCatalog();
    final rows = <List<dynamic>>[_csvHeader];
    for (final p in catalog) {
      rows.add([
        p.sku ?? '',
        p.displayName,
        p.vendor ?? '',
        '', // costo (lo llena el centro)
        p.price?.toStringAsFixed(2) ?? '',
        p.currency ?? 'MXN',
        '', // cantidad inicial (lo llena el centro)
        p.shopifyProductId,
        p.shopifyVariantId ?? '',
      ]);
    }
    // Fila-ejemplo de producto NUEVO (sin ids de Shopify = externo).
    rows.add([
      'SKU-EJEMPLO',
      'Producto propio del centro (ejemplo)',
      'Proveedor',
      '0.00',
      '0.00',
      'MXN',
      '0',
      '',
      '',
    ]);
    final content = const ListToCsvConverter().convert(rows);
    try {
      await downloadCsv('inventario_catalogo.csv', content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo descargar: $e')));
      }
    }
  }

  /// Carga un CSV y crea/repone artículos de inventario en el sitio actual.
  /// Con shopify_product_id → artículo ligado al catálogo; sin él → externo.
  Future<void> _uploadCsv(DataRepository repo, String? orgId) async {
    final siteId = _siteId;
    if (orgId == null || siteId == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    setState(() => _importing = true);
    try {
      final content = String.fromCharCodes(bytes);
      final raw = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
          .convert(content);
      if (raw.isEmpty) throw 'CSV vacío.';

      // Índice de columnas por encabezado (tolerante al orden).
      final header =
          raw.first.map((e) => e.toString().trim().toLowerCase()).toList();
      int col(String name) => header.indexOf(name);
      final iSku = col('sku'),
          iName = col('nombre'),
          iProv = col('proveedor'),
          iCost = col('costo'),
          iPrice = col('precio'),
          iCur = col('moneda'),
          iQty = col('cantidad'),
          iPid = col('shopify_product_id'),
          iVid = col('shopify_variant_id');
      if (iName < 0) throw 'Falta la columna "nombre".';

      final existing =
          repo.listInventoryItems(organizationId: orgId, siteId: siteId);
      final uid = ref.read(sessionProvider).user?.id;
      String? cell(List<dynamic> r, int i) =>
          i >= 0 && i < r.length ? r[i].toString().trim() : null;
      double? toNum(String? s) =>
          (s == null || s.isEmpty) ? null : double.tryParse(s.replaceAll(',', '.'));

      var created = 0, restocked = 0, skipped = 0;
      for (var k = 1; k < raw.length; k++) {
        final r = raw[k];
        final name = cell(r, iName) ?? '';
        if (name.isEmpty) continue;
        final pid = cell(r, iPid);
        final vid = cell(r, iVid);
        final qty = (toNum(cell(r, iQty)) ?? 0).round();
        final cost = toNum(cell(r, iCost));
        final price = toNum(cell(r, iPrice));
        final cur = cell(r, iCur);
        final sku = cell(r, iSku);
        final prov = cell(r, iProv);

        // ¿Ya existe? (por producto de Shopify si hay id; si no, por nombre.)
        InventoryItem? match;
        for (final it in existing) {
          final same = (pid != null && pid.isNotEmpty)
              ? it.shopifyProductId == pid
              : it.name.toLowerCase() == name.toLowerCase();
          if (same) {
            match = it;
            break;
          }
        }

        if (match == null) {
          final item = await repo.addInventoryItem(
            organizationId: orgId,
            siteId: siteId,
            name: name,
            isExternal: pid == null || pid.isEmpty,
            shopifyProductId: (pid != null && pid.isNotEmpty) ? pid : null,
            shopifyVariantId: (vid != null && vid.isNotEmpty) ? vid : null,
            unitCost: cost,
            unitPrice: price,
            currency: cur,
            supplier: (prov != null && prov.isNotEmpty) ? prov : null,
            notes: (sku != null && sku.isNotEmpty) ? 'SKU: $sku' : null,
            createdBy: uid,
          );
          created++;
          if (qty > 0) {
            await repo.addInventoryMovement(
              item: item,
              delta: qty,
              reason: InventoryReason.compra,
              unitCost: cost,
              note: 'Carga inicial (CSV)',
              createdBy: uid,
            );
          }
        } else if (qty > 0) {
          await repo.addInventoryMovement(
            item: match,
            delta: qty,
            reason: InventoryReason.compra,
            unitCost: cost,
            note: 'Reabasto (CSV)',
            createdBy: uid,
          );
          restocked++;
        } else {
          skipped++;
        }
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'CSV: $created creados, $restocked reabastecidos'
                '${skipped > 0 ? ', $skipped sin cambios' : ''}.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo cargar el CSV: $e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          if (repoAsync.valueOrNull
                  ?.premiumInsumosFor(user?.organizationId) ??
              false) ...[
            IconButton(
              tooltip: 'Descargar CSV (catálogo)',
              icon: const Icon(Icons.download_outlined),
              onPressed: () =>
                  _downloadCsv(repoAsync.value!, user?.organizationId),
            ),
            IconButton(
              tooltip: 'Cargar CSV',
              icon: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_outlined),
              onPressed: _importing
                  ? null
                  : () => _uploadCsv(repoAsync.value!, user?.organizationId),
            ),
          ],
          const UserMenuButton(),
        ],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final orgId = user?.organizationId;
          if (!repo.premiumInsumosFor(orgId)) return const _PremiumLocked();

          final sites =
              repo.listSites(organizationId: orgId).where((s) => s.isActive).toList();
          if (sites.isEmpty) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Este centro no tiene sitios configurados.')));
          }
          // Alcance del inventario (0053): 'center' = una sola bolsa (sitio
          // principal, sin selector); 'site' = por sitio con selector.
          final scope = repo.inventoryScopeFor(orgId);
          final centerMode = scope == 'center';
          if (centerMode) {
            _siteId = sites.first.id;
          } else {
            _siteId ??= repo.primarySiteIdForProfile(user?.id) ?? sites.first.id;
            if (!sites.any((s) => s.id == _siteId)) _siteId = sites.first.id;
          }

          final items = repo.listInventoryItems(organizationId: orgId, siteId: _siteId);
          final onHand = repo.inventoryOnHand(_siteId!);
          final lowCount = items
              .where((it) =>
                  it.reorderThreshold != null &&
                  (onHand[it.id] ?? 0) <= it.reorderThreshold!)
              .length;
          final invValue = items.fold<double>(
              0, (a, it) => a + (it.unitCost ?? 0) * (onHand[it.id] ?? 0));
          final isAdmin = user?.role == AppRole.admin;

          return Column(
            children: [
              _InvSummary(
                total: items.length,
                low: lowCount,
                value: invValue,
                scope: scope,
                canEditScope: isAdmin,
                onScope: (s) async {
                  await repo.setInventoryScope(orgId!, s);
                  if (mounted) setState(() {});
                },
              ),
              if (!centerMode && sites.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
                child: items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Sin artículos en este sitio.\n'
                            'Agrega productos de tu tienda o externos.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _ItemTile(
                          item: items[i],
                          onHand: onHand[items[i].id] ?? 0,
                          onTap: () => _openItem(repo, items[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: repoAsync.valueOrNull != null &&
              repoAsync.value!.premiumInsumosFor(user?.organizationId)
          ? FloatingActionButton.extended(
              onPressed: () => _addItem(repoAsync.value!, user?.organizationId),
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            )
          : null,
    );
  }

  // ---- Alta de artículo ----
  Future<void> _addItem(DataRepository repo, String? orgId) async {
    if (orgId == null || _siteId == null) return;
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Producto de la tienda Kura+'),
              subtitle: const Text('Trae foto y precio; se puede reabastecer.'),
              onTap: () => Navigator.of(context).pop('store'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Producto externo (otro proveedor)'),
              subtitle: const Text('Captura manual: nombre, costo, proveedor.'),
              onTap: () => Navigator.of(context).pop('external'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    InventoryItem? created;
    if (kind == 'store') {
      final picked = await showShopifyProductPicker(context,
          title: 'Agregar producto de la tienda al inventario');
      if (picked == null) return;
      final price = picked.variant?.price ?? picked.product.fromPrice;
      created = await repo.addInventoryItem(
        organizationId: orgId,
        siteId: _siteId!,
        name: picked.product.title,
        shopifyProductId: picked.product.id,
        shopifyVariantId: picked.variant?.id,
        imageUrl: picked.product.imageUrl,
        unitCost: price?.amount,
        currency: price?.currencyCode,
        createdBy: ref.read(sessionProvider).user?.id,
      );
    } else {
      created = await _externalForm(repo, orgId);
    }
    if (created == null || !mounted) return;
    setState(() {});
    // Ofrecer registrar existencia inicial.
    await _movementDialog(repo, created, sign: 1, title: 'Existencia inicial',
        reasons: const [InventoryReason.conteo, InventoryReason.compra]);
  }

  Future<InventoryItem?> _externalForm(DataRepository repo, String orgId) async {
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final supplierCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
        title: const Text('Producto externo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
              ),
              TextField(
                controller: supplierCtrl,
                decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
              ),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Costo unitario (opcional)'),
                // Autocompleta el precio con costo +30% (editable).
                onChanged: (v) {
                  final c = double.tryParse(v.trim());
                  if (c != null) {
                    priceCtrl.text = (c * 1.3).toStringAsFixed(2);
                    setD(() {});
                  }
                },
              ),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Precio de venta (default costo +30%)'),
              ),
              TextField(
                controller: thresholdCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Umbral de reorden (opcional)'),
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
              child: const Text('Crear')),
        ],
      ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return null;
    return repo.addInventoryItem(
      organizationId: orgId,
      siteId: _siteId!,
      name: nameCtrl.text.trim(),
      isExternal: true,
      unitCost: double.tryParse(costCtrl.text.trim()),
      unitPrice: double.tryParse(priceCtrl.text.trim()),
      supplier: supplierCtrl.text.trim().isEmpty ? null : supplierCtrl.text.trim(),
      reorderThreshold: int.tryParse(thresholdCtrl.text.trim()),
      createdBy: ref.read(sessionProvider).user?.id,
    );
  }

  // ---- Detalle del artículo ----
  Future<void> _openItem(DataRepository repo, InventoryItem item) async {
    final isAdmin = ref.read(sessionProvider).user?.role == AppRole.admin;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemDetailSheet(
        repo: repo,
        item: item,
        onEntrada: () => _movementDialog(repo, item, sign: 1,
            title: 'Entrada / reabasto',
            reasons: const [InventoryReason.compra, InventoryReason.devolucion]),
        onSalida: () => _movementDialog(repo, item, sign: -1, title: 'Salida',
            reasons: const [InventoryReason.consumo, InventoryReason.merma]),
        onAjuste: () => _adjustDialog(repo, item),
        onEditPrices: isAdmin
            ? () {
                Navigator.of(context).pop();
                _editPrices(repo, item);
              }
            : null,
      ),
    );
    if (mounted) setState(() {});
  }

  /// Editar costo y precio del insumo (solo admin). El precio es el que se cobra
  /// al paciente; al cambiar el costo se sugiere costo +30% (editable).
  Future<void> _editPrices(DataRepository repo, InventoryItem item) async {
    final costCtrl = TextEditingController(
        text: item.unitCost == null ? '' : '${item.unitCost}');
    final priceCtrl = TextEditingController(
        text: item.unitPrice == null ? '' : '${item.unitPrice}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Costo y precio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Costo (del centro)'),
                onChanged: (v) {
                  final c = double.tryParse(v.trim());
                  if (c != null) {
                    priceCtrl.text = (c * 1.3).toStringAsFixed(2);
                    setD(() {});
                  }
                },
              ),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Precio de venta (al paciente)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await repo.updateInventoryItem(
      item.id,
      unitCost: double.tryParse(costCtrl.text.trim()),
      unitPrice: double.tryParse(priceCtrl.text.trim()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _movementDialog(DataRepository repo, InventoryItem item,
      {required int sign,
      required String title,
      required List<InventoryReason> reasons}) async {
    final qtyCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var reason = reasons.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Cantidad (piezas)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<InventoryReason>(
                value: reason,
                decoration: const InputDecoration(labelText: 'Motivo'),
                items: [
                  for (final r in reasons)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) => setD(() => reason = v ?? reason),
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Registrar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) return;
    await repo.addInventoryMovement(
      item: item,
      delta: sign * qty,
      reason: reason,
      unitCost: sign > 0 ? item.unitCost : null,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      createdBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) setState(() {});
  }

  Future<void> _adjustDialog(DataRepository repo, InventoryItem item) async {
    final current = repo.onHandFor(item.id);
    final ctrl = TextEditingController(text: '$current');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajuste por conteo físico'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Existencia actual: $current'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Existencia real (conteo)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ajustar')),
        ],
      ),
    );
    if (ok != true) return;
    final real = int.tryParse(ctrl.text.trim());
    if (real == null) return;
    final delta = real - current;
    if (delta == 0) return;
    await repo.addInventoryMovement(
      item: item,
      delta: delta,
      reason: InventoryReason.conteo,
      note: 'Ajuste por conteo físico',
      createdBy: ref.read(sessionProvider).user?.id,
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
          child: Text('El inventario es una función premium.',
              textAlign: TextAlign.center),
        ),
      );
}

class _ItemTile extends StatelessWidget {
  final InventoryItem item;
  final int onHand;
  final VoidCallback onTap;
  const _ItemTile({required this.item, required this.onHand, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final low = item.reorderThreshold != null && onHand <= item.reorderThreshold!;
    final stockColor = onHand <= 0
        ? KuraColors.danger
        : (low ? KuraColors.warning : KuraColors.success);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 44,
            height: 44,
            color: KuraColors.chipBg,
            child: item.imageUrl == null
                ? Icon(item.isExternal ? Icons.inventory_2_outlined : Icons.medical_services_outlined,
                    size: 20)
                : Image.network(item.imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.image_not_supported_outlined, size: 20)),
          ),
        ),
        title: Text(item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            item.isExternal ? 'Externo' : 'Tienda Kura+',
            if (item.supplier != null && item.supplier!.isNotEmpty) item.supplier!,
            if (item.unitCost != null) 'Costo ${_money(item.unitCost, item.currency)}',
            if (item.unitPrice != null) 'Precio ${_money(item.unitPrice, item.currency)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$onHand',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: stockColor)),
            Text(low ? 'Reordenar' : 'en stock',
                style: TextStyle(fontSize: 10, color: stockColor)),
          ],
        ),
      ),
    );
  }
}

class _ItemDetailSheet extends StatelessWidget {
  final DataRepository repo;
  final InventoryItem item;
  final Future<void> Function() onEntrada;
  final Future<void> Function() onSalida;
  final Future<void> Function() onAjuste;
  final VoidCallback? onEditPrices; // solo admin
  const _ItemDetailSheet({
    required this.repo,
    required this.item,
    required this.onEntrada,
    required this.onSalida,
    required this.onAjuste,
    this.onEditPrices,
  });

  @override
  Widget build(BuildContext context) {
    final onHand = repo.onHandFor(item.id);
    final movements = repo.listInventoryMovements(inventoryItemId: item.id);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              [
                item.isExternal ? 'Externo' : 'Tienda Kura+',
                if (item.supplier != null && item.supplier!.isNotEmpty) item.supplier!,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Costo ${_money(item.unitCost, item.currency)}   ·   '
                    'Precio ${_money(item.unitPrice, item.currency)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (onEditPrices != null)
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar'),
                    onPressed: onEditPrices,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Existencia: ',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text('$onHand',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                if (item.reorderThreshold != null) ...[
                  const SizedBox(width: 8),
                  Text('(umbral ${item.reorderThreshold})',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Entrada'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await onEntrada();
                  },
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.remove, size: 18),
                  label: const Text('Salida'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await onSalida();
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Ajuste'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await onAjuste();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Movimientos', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Flexible(
              child: movements.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Sin movimientos.'))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: movements.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (_, i) {
                        final m = movements[i];
                        final pos = m.delta > 0;
                        return Row(
                          children: [
                            Text(pos ? '+${m.delta}' : '${m.delta}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: pos
                                        ? KuraColors.success
                                        : KuraColors.danger)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.reason.label,
                                      style: const TextStyle(fontSize: 13)),
                                  Text(
                                    '${fmt.format(m.createdAt)}'
                                    '${m.note != null && m.note!.isNotEmpty ? ' · ${m.note}' : ''}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resumen del inventario (mini-dashboard): total de artículos, cuántos bajo su
/// umbral y el valor del inventario. El admin puede fijar el alcance (por sitio
/// o por centro).
class _InvSummary extends StatelessWidget {
  final int total;
  final int low;
  final double value;
  final String scope; // 'site' | 'center'
  final bool canEditScope;
  final ValueChanged<String> onScope;
  const _InvSummary({
    required this.total,
    required this.low,
    required this.value,
    required this.scope,
    required this.canEditScope,
    required this.onScope,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                _kpi(context, '$total', 'Artículos', KuraColors.primary),
                _kpi(context, '$low', 'Reordenar',
                    low > 0 ? KuraColors.warning : KuraColors.success),
                _kpi(context, _money(value), 'Valor', KuraColors.darkText),
              ],
            ),
            if (canEditScope) ...[
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.tune, size: 16),
                  const SizedBox(width: 8),
                  const Text('Inventario:', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SegmentedButton<String>(
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: 'site', label: Text('Por sitio')),
                        ButtonSegment(value: 'center', label: Text('Por centro')),
                      ],
                      selected: {scope},
                      onSelectionChanged: (s) => onScope(s.first),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpi(BuildContext context, String v, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(v,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
