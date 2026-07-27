import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/commercial.dart';
import '../../services/data_repository.dart';
import '../insumos/dashboard_charts.dart';

String _money(double v) => '\$${v.toStringAsFixed(2)} MXN';

/// Módulo comercial (Fase C, premium): historial de cobros/pagos y catálogo de
/// servicios del centro. A futuro: facturación. Gateado por premium_insumos.
class ComercialScreen extends ConsumerWidget {
  const ComercialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return repoAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (repo) {
        final orgId = user?.organizationId;
        if (!repo.premiumInsumosFor(orgId)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Comercial')),
            body: const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('El módulo comercial es una función premium.',
                        textAlign: TextAlign.center))),
          );
        }
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Comercial'),
              actions: const [UserMenuButton()],
              bottom: const TabBar(tabs: [
                Tab(text: 'Resumen'),
                Tab(text: 'Cobros'),
                Tab(text: 'Servicios'),
              ]),
            ),
            body: TabBarView(children: [
              _ResumenTab(repo: repo, orgId: orgId),
              _CobrosTab(repo: repo, orgId: orgId),
              _ServiciosTab(repo: repo, orgId: orgId),
            ]),
          ),
        );
      },
    );
  }
}

class _CobrosTab extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? orgId;
  const _CobrosTab({required this.repo, required this.orgId});
  @override
  ConsumerState<_CobrosTab> createState() => _CobrosTabState();
}

class _CobrosTabState extends ConsumerState<_CobrosTab> {
  ChargeStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final all = repo.listCharges(organizationId: widget.orgId);
    final paid = all.where((c) => c.status == ChargeStatus.pagado).fold<double>(0, (a, c) => a + c.total);
    final pending = all.where((c) => c.status == ChargeStatus.pendiente).fold<double>(0, (a, c) => a + c.total);
    final list = _filter == null ? all : all.where((c) => c.status == _filter).toList();
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(child: _KpiBox(label: 'Cobrado', value: _money(paid), color: KuraColors.success)),
              const SizedBox(width: 10),
              Expanded(child: _KpiBox(label: 'Pendiente', value: _money(pending), color: KuraColors.warning)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final f in [null, ChargeStatus.pendiente, ChargeStatus.pagado, ChargeStatus.cancelado])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f == null ? 'Todos' : f.label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Sin cobros.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final patient = c.patientId == null ? null : repo.getPatient(c.patientId!);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(patient?.fullName ?? 'Paciente'),
                      subtitle: Text('${fmt.format(c.createdAt)} · ${c.status.label}'
                          '${c.paymentMethod != null ? ' · ${c.paymentMethod}' : ''}'),
                      trailing: Text(_money(c.total),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      onTap: () => _openCharge(repo, c),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _openCharge(DataRepository repo, Charge c) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChargeDetailSheet(repo: repo, charge: c),
    );
    if (mounted) setState(() {});
  }
}

class _ChargeDetailSheet extends StatelessWidget {
  final DataRepository repo;
  final Charge charge;
  const _ChargeDetailSheet({required this.repo, required this.charge});

  @override
  Widget build(BuildContext context) {
    final items = repo.listChargeItems(charge.id);
    final patient = charge.patientId == null ? null : repo.getPatient(charge.patientId!);
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 4, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(patient?.fullName ?? 'Cobro',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text('${charge.status.label}'
              '${charge.paymentMethod != null ? ' · ${charge.paymentMethod}' : ''}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text('${it.name}${it.quantity > 1 ? '  ×${it.quantity}' : ''}',
                      style: const TextStyle(fontSize: 13))),
                  Text(_money(it.lineTotal)),
                ],
              ),
            ),
          const Divider(),
          Row(children: [
            const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
            Text(_money(charge.total), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          if (charge.status == ChargeStatus.pendiente)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await repo.cancelCharge(charge.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Cancelar cobro'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    final method = await _pickMethod(context);
                    if (method == null) return;
                    await repo.markChargePaid(charge.id, method);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Registrar pago'),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Future<String?> _pickMethod(BuildContext context) => showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in const [
                ('efectivo', 'Efectivo'),
                ('transferencia', 'Transferencia'),
                ('tarjeta', 'Tarjeta (manual)'),
              ])
                ListTile(
                  title: Text(m.$2),
                  onTap: () => Navigator.of(ctx).pop(m.$1),
                ),
            ],
          ),
        ),
      );
}

class _ServiciosTab extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? orgId;
  const _ServiciosTab({required this.repo, required this.orgId});
  @override
  ConsumerState<_ServiciosTab> createState() => _ServiciosTabState();
}

class _ServiciosTabState extends ConsumerState<_ServiciosTab> {
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final services = repo.listServices(widget.orgId, activeOnly: false);
    return Scaffold(
      body: services.isEmpty
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Sin servicios. Agrega los honorarios de tu centro '
                      '(Valoración, Seguimiento, Curación…).',
                      textAlign: TextAlign.center)))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: services.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = services[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.name,
                      style: TextStyle(
                          decoration: s.isActive ? null : TextDecoration.lineThrough)),
                  subtitle: Text(_money(s.price)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') await _edit(repo, s);
                      if (v == 'toggle') {
                        await repo.updateService(s.id, isActive: !s.isActive);
                        if (mounted) setState(() {});
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(
                          value: 'toggle',
                          child: Text(s.isActive ? 'Desactivar' : 'Activar')),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(repo, null),
        icon: const Icon(Icons.add),
        label: const Text('Servicio'),
      ),
    );
  }

  Future<void> _edit(DataRepository repo, ServiceCatalogItem? s) async {
    if (widget.orgId == null) return;
    final nameCtrl = TextEditingController(text: s?.name ?? '');
    final priceCtrl = TextEditingController(text: s == null ? '' : '${s.price}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s == null ? 'Nuevo servicio' : 'Editar servicio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre *'),
            ),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Honorario (MXN) *'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
    if (name.isEmpty) return;
    if (s == null) {
      await repo.addService(
          organizationId: widget.orgId!,
          name: name,
          price: price,
          createdBy: ref.read(sessionProvider).user?.id);
    } else {
      await repo.updateService(s.id, name: name, price: price);
    }
    if (mounted) setState(() {});
  }
}

class _KpiBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _KpiBox({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

/// Pestaña Resumen: dashboard comercial con gráficos + tarjetas de acceso.
class _ResumenTab extends StatelessWidget {
  final DataRepository repo;
  final String? orgId;
  const _ResumenTab({required this.repo, required this.orgId});

  @override
  Widget build(BuildContext context) {
    final charges = repo.listCharges(organizationId: orgId);
    final paid = charges.where((c) => c.status == ChargeStatus.pagado).toList();
    final paidTotal = paid.fold<double>(0, (a, c) => a + c.total);
    final pendingTotal = charges
        .where((c) => c.status == ChargeStatus.pendiente)
        .fold<double>(0, (a, c) => a + c.total);

    // Por método de pago.
    final byMethod = <String, double>{};
    for (final c in paid) {
      final k = c.paymentMethod ?? 'otro';
      byMethod[k] = (byMethod[k] ?? 0) + c.total;
    }
    Color methodColor(String m) => switch (m) {
          'efectivo' => KuraColors.success,
          'transferencia' => KuraColors.infoBlue,
          'tarjeta' => KuraColors.primary,
          'stripe' => KuraColors.primary,
          _ => KuraColors.darkText,
        };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(children: [
          Expanded(child: _KpiBox(label: 'Cobrado', value: _money(paidTotal), color: KuraColors.success)),
          const SizedBox(width: 10),
          Expanded(child: _KpiBox(label: 'Pendiente', value: _money(pendingTotal), color: KuraColors.warning)),
        ]),
        const SizedBox(height: 12),
        _IngresosChartCard(repo: repo, orgId: orgId),
        const SizedBox(height: 12),
        DonutCard(
          title: 'Cobrado por método de pago',
          slices: [
            for (final e in byMethod.entries) DonutSlice(e.key, e.value, methodColor(e.key)),
          ],
        ),
        const SizedBox(height: 16),
        _ProcessCard(
          icon: Icons.receipt_long_outlined,
          title: 'Cobros',
          subtitle: 'Historial de cobros y pagos; marcar pagado o cancelar.',
          onTap: () => DefaultTabController.of(context).animateTo(1),
        ),
        _ProcessCard(
          icon: Icons.sell_outlined,
          title: 'Servicios',
          subtitle: 'Catálogo de honorarios del centro.',
          onTap: () => DefaultTabController.of(context).animateTo(2),
        ),
      ],
    );
  }
}

class _ProcessCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ProcessCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 10),
        child: ListTile(
          leading: Icon(icon, color: KuraColors.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

/// Gráfico "Ingresos por mes" con filtro por servicio (Todos o un servicio).
class _IngresosChartCard extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? orgId;
  const _IngresosChartCard({required this.repo, required this.orgId});
  @override
  ConsumerState<_IngresosChartCard> createState() => _IngresosChartCardState();
}

class _IngresosChartCardState extends ConsumerState<_IngresosChartCard> {
  String? _service; // null = todos

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final paid = repo
        .listCharges(organizationId: widget.orgId)
        .where((c) => c.status == ChargeStatus.pagado)
        .toList();

    // Servicio de cada cobro = renglón kind 'servicio' de su desglose.
    String serviceOf(Charge c) {
      final items = repo.listChargeItems(c.id);
      for (final it in items) {
        if (it.kind == 'servicio') return it.name;
      }
      return 'Otro';
    }

    final serviceByCharge = {for (final c in paid) c.id: serviceOf(c)};
    final services = serviceByCharge.values.toSet().toList()..sort();
    if (_service != null && !services.contains(_service)) _service = null;

    final filtered = _service == null
        ? paid
        : paid.where((c) => serviceByCharge[c.id] == _service).toList();

    final now = DateTime.now();
    final months = <MonthValue>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final next = DateTime(m.year, m.month + 1, 1);
      final v = filtered.where((c) {
        final d = c.paidAt ?? c.createdAt;
        return !d.isBefore(m) && d.isBefore(next);
      }).fold<double>(0, (a, c) => a + c.total);
      months.add(MonthValue(kMonthShort[m.month - 1], v));
    }

    return MonthlyBarChart(
      title: 'Ingresos por mes',
      data: months,
      color: KuraColors.success,
      valueLabel: (v) => '\$${v.toInt()}',
      headerTrailing: services.isEmpty
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: DropdownButton<String?>(
                value: _service,
                isExpanded: true,
                isDense: true,
                underline: const SizedBox.shrink(),
                hint: const Text('Servicio', style: TextStyle(fontSize: 12)),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos', style: TextStyle(fontSize: 12))),
                  for (final s in services)
                    DropdownMenuItem<String?>(
                        value: s,
                        child: Text(s,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12))),
                ],
                onChanged: (v) => setState(() => _service = v),
              ),
            ),
    );
  }
}
