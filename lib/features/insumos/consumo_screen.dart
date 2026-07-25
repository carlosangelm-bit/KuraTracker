import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/inventory.dart';
import '../../models/supply_product_mapping.dart';
import '../../services/data_repository.dart';

String _money(double v) => '\$${v.toStringAsFixed(2)} MXN';

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

/// Consumo de insumos por paciente + costeo (Insumos, Fase 4 premium). Registra
/// las salidas de inventario ligadas a un paciente (descuenta stock) y muestra
/// el costo del tratamiento. Sugiere qué descontar a partir del plan (Fase 2).
class ConsumoScreen extends ConsumerStatefulWidget {
  const ConsumoScreen({super.key});
  @override
  ConsumerState<ConsumoScreen> createState() => _ConsumoScreenState();
}

class _ConsumoScreenState extends ConsumerState<ConsumoScreen> {
  String? _patientId;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consumo por paciente'),
        actions: [
          if (_patientId != null)
            TextButton(
              onPressed: () => setState(() => _patientId = null),
              child: const Text('Cambiar', style: TextStyle(color: Colors.white)),
            ),
          const UserMenuButton(),
        ],
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
                    child: Text('El consumo por paciente es una función premium.',
                        textAlign: TextAlign.center)));
          }
          return _patientId == null
              ? _patientPicker(repo, orgId)
              : _patientConsumption(repo, orgId!);
        },
      ),
    );
  }

  Widget _patientPicker(DataRepository repo, String? orgId) {
    final q = _fold(_search);
    final patients = repo
        .listAllPatients()
        .where((p) => p.organizationId == orgId)
        .where((p) => q.isEmpty || _fold(p.fullName).contains(q))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Buscar paciente…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: patients.isEmpty
              ? const Center(child: Text('Sin pacientes.'))
              : ListView.separated(
                  itemCount: patients.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(patients[i].fullName),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() {
                      _patientId = patients[i].id;
                      _search = '';
                    }),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _patientConsumption(DataRepository repo, String orgId) {
    final patient = repo.getPatient(_patientId!);
    if (patient == null) {
      return const Center(child: Text('Paciente no encontrado.'));
    }
    final sites = repo.listSites(organizationId: orgId).where((s) => s.isActive).toList();
    final siteId = patient.primarySiteId ?? (sites.isNotEmpty ? sites.first.id : null);
    if (siteId == null) {
      return const Center(child: Text('El centro no tiene sitios configurados.'));
    }
    final inventory = repo.listInventoryItems(organizationId: orgId, siteId: siteId);
    final onHand = repo.inventoryOnHand(siteId);
    final consumo = repo.listConsumptionForPatient(_patientId!);
    final cost = repo.consumptionCostForPatient(_patientId!);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    // Sugerencias del plan: componentes del plan más reciente → mapeo (Fase 2)
    // → artículo de inventario del sitio (si existe).
    final mapIndex = repo.supplyMappingIndex(orgId);
    final byShopifyProduct = <String, InventoryItem>{
      for (final it in inventory)
        if (it.shopifyProductId != null) it.shopifyProductId!: it
    };
    final suggestions = <InventoryItem>[];
    final seen = <String>{};
    for (final comp in repo.latestTreatmentComponentsForPatient(_patientId!)) {
      final m = mapIndex[SupplyProductMapping.keyFor(comp.method, comp.product)];
      if (m == null) continue;
      final item = byShopifyProduct[m.shopifyProductId];
      if (item != null && seen.add(item.id)) suggestions.add(item);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(patient.fullName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: KuraColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Expanded(
                  child: Text('Costo de insumos consumidos',
                      style: TextStyle(fontWeight: FontWeight.w600))),
              Text(_money(cost),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: KuraColors.primary)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (suggestions.isNotEmpty) ...[
          const Text('Sugerencias del plan de tratamiento',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Insumos del plan que están mapeados y en inventario.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final it in suggestions)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text('${it.name}  ·  ${onHand[it.id] ?? 0}'),
                  onPressed: () => _registerConsumo(repo, it, onHand[it.id] ?? 0),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.remove_shopping_cart_outlined, size: 18),
            label: const Text('Registrar consumo'),
            onPressed: inventory.isEmpty
                ? null
                : () => _pickAndConsume(repo, inventory, onHand),
          ),
        ),
        if (inventory.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No hay inventario en el sitio de este paciente.',
                style: TextStyle(fontSize: 12, color: KuraColors.darkText)),
          ),
        const SizedBox(height: 16),

        const Text('Consumo registrado', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (consumo.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Aún no hay consumo registrado para este paciente.'),
          )
        else
          ...consumo.map((m) {
            final item = inventory.firstWhere(
              (it) => it.id == m.inventoryItemId,
              orElse: () => repo
                  .listInventoryItems(activeOnly: false)
                  .firstWhere((it) => it.id == m.inventoryItemId,
                      orElse: () => InventoryItem(
                          id: m.inventoryItemId,
                          organizationId: orgId,
                          siteId: siteId,
                          name: 'Artículo')),
            );
            final lineCost = (m.unitCost ?? item.unitCost ?? 0) * m.delta.abs();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text('${m.delta.abs()}×',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontSize: 13)),
                        Text(fmt.format(m.createdAt),
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  Text(_money(lineCost),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
      ],
    );
  }

  Future<void> _pickAndConsume(DataRepository repo, List<InventoryItem> inventory,
      Map<String, int> onHand) async {
    final item = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Elegir insumo del inventario',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final it in inventory)
                ListTile(
                  title: Text(it.name),
                  subtitle: Text('En stock: ${onHand[it.id] ?? 0}'),
                  onTap: () => Navigator.of(context).pop(it),
                ),
            ],
          ),
        ),
      ),
    );
    if (item == null || !mounted) return;
    await _registerConsumo(repo, item, onHand[item.id] ?? 0);
  }

  Future<void> _registerConsumo(
      DataRepository repo, InventoryItem item, int stock) async {
    final qtyCtrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar consumo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('En stock: $stock'),
            const SizedBox(height: 8),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Cantidad consumida'),
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
    );
    if (ok != true) return;
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) return;
    if (qty > stock && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Existencia insuficiente'),
          content: Text('Solo hay $stock en stock. ¿Registrar $qty de todos modos '
              '(la existencia quedará negativa)?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('No')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Sí, registrar')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    await repo.addInventoryMovement(
      item: item,
      delta: -qty,
      reason: InventoryReason.consumo,
      unitCost: item.unitCost,
      patientId: _patientId,
      createdBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) setState(() {});
  }
}
