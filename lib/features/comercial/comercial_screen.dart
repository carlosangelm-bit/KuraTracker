import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/layout/responsive.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart'
    show UserMenuButton, kFloatingNavBarHeight;
import '../../models/commercial.dart';
import '../../models/inventory.dart';
import '../../models/patient.dart';
import 'materials_explosion_screen.dart';
import '../../services/acuity_service.dart';
import '../../services/data_repository.dart';
import '../insumos/dashboard_charts.dart';

String _money(double v) => '\$${v.toStringAsFixed(2)} MXN';

/// Módulo comercial (Fase C, premium): historial de cobros/pagos y catálogo de
/// servicios del centro. A futuro: facturación. Gateado por premium_insumos.
class ComercialScreen extends ConsumerStatefulWidget {
  const ComercialScreen({super.key});

  @override
  ConsumerState<ComercialScreen> createState() => _ComercialScreenState();
}

class _ComercialScreenState extends ConsumerState<ComercialScreen>
    with SingleTickerProviderStateMixin {
  int _section = 0;
  late final TabController _tabController =
      TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _go(int i) => setState(() {
        _section = i;
        _tabController.index = i;
      });

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return repoAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (repo) {
        final orgId = user?.organizationId;
        if (!repo.premiumInsumosFor(orgId)) {
          return Scaffold(
            appBar: AppBar(
                title: const Text('Comercial'),
                actions: const [UserMenuButton()]),
            body: const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('El módulo comercial es una función premium.',
                        textAlign: TextAlign.center))),
          );
        }
        final wide =
            MediaQuery.of(context).size.width >= Breakpoints.twoPane;
        Widget content() => switch (_section) {
              1 => _CobrosTab(repo: repo, orgId: orgId),
              2 => _ConciliacionTab(repo: repo, orgId: orgId),
              3 => _ServiciosTab(repo: repo, orgId: orgId),
              4 => const _FacturacionTab(),
              _ => _ResumenTab(repo: repo, orgId: orgId, onOpenSection: _go),
            };
        return Scaffold(
          appBar: AppBar(
            title: const Text('Comercial'),
            actions: const [UserMenuButton()],
            bottom: wide
                ? null
                : TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    onTap: _go,
                    tabs: const [
                      Tab(text: 'Resumen'),
                      Tab(text: 'Cobros'),
                      Tab(text: 'Conciliación'),
                      Tab(text: 'Servicios'),
                      Tab(text: 'Facturación'),
                    ],
                  ),
          ),
          body: wide
              ? Row(
                  children: [
                    SectionRail(
                      selectedIndex: _section,
                      onSelected: _go,
                      destinations: const [
                        (Icons.dashboard_outlined, 'Resumen'),
                        (Icons.receipt_long_outlined, 'Cobros'),
                        (Icons.sync_alt_outlined, 'Conciliación'),
                        (Icons.sell_outlined, 'Servicios'),
                        (Icons.description_outlined, 'Facturación'),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content()),
                  ],
                )
              : content(),
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
  Object? _sub;

  @override
  void initState() {
    super.initState();
    // Realtime: refresca la lista en cuanto un cobro cambia (p. ej. el webhook
    // de Stripe lo marca Pagado), sin tener que recargar la página.
    _sub = widget.repo.watchCollection('charges', () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.repo.unwatch(_sub);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final all = repo.listCharges(organizationId: widget.orgId);
    final paid = all.where((c) => c.status == ChargeStatus.pagado).fold<double>(0, (a, c) => a + c.total);
    final pending = all.where((c) => c.status == ChargeStatus.pendiente).fold<double>(0, (a, c) => a + c.total);
    final list = _filter == null ? all : all.where((c) => c.status == _filter).toList();
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nuevoCobro(repo),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo cobro'),
      ),
      body: Column(
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
      ),
    );
  }

  Future<void> _nuevoCobro(DataRepository repo) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewChargeSheet(repo: repo, orgId: widget.orgId),
    );
    if (created == true && mounted) setState(() {});
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

/// Renglón en construcción del cobro directo (servicio o producto).
class _ChargeLine {
  final String kind; // 'servicio' | 'insumo'
  final String name;
  final double unitPrice;
  final String? inventoryItemId;
  int quantity = 1;
  _ChargeLine({
    required this.kind,
    required this.name,
    required this.unitPrice,
    this.inventoryItemId,
  });
  double get lineTotal => unitPrice * quantity;
}

/// Builder de un cobro DIRECTO (sin consulta) desde la pestaña Cobros: elige
/// tipos de consulta (servicios) y productos (inventario); paciente opcional.
class _NewChargeSheet extends StatefulWidget {
  final DataRepository repo;
  final String? orgId;
  const _NewChargeSheet({required this.repo, required this.orgId});
  @override
  State<_NewChargeSheet> createState() => _NewChargeSheetState();
}

class _NewChargeSheetState extends State<_NewChargeSheet> {
  Patient? _patient;
  final List<_ChargeLine> _lines = [];
  bool _busy = false;

  double get _total => _lines.fold(0, (a, l) => a + l.lineTotal);

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickPatient() async {
    final all = widget.repo
        .listAllPatients()
        .where((p) => widget.orgId == null || p.organizationId == widget.orgId)
        .toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    final picked = await showModalBottomSheet<Patient>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchPickerSheet<Patient>(
        title: 'Ligar paciente',
        items: all,
        labelOf: (p) => p.fullName,
        sublabelOf: (p) => p.folio,
      ),
    );
    if (picked != null) setState(() => _patient = picked);
  }

  Future<void> _addServicio() async {
    final services = widget.repo
        .listServices(widget.orgId)
        .where((s) => s.isActive)
        .toList();
    if (services.isEmpty) {
      _snack('No hay tipos de consulta en el catálogo de servicios.');
      return;
    }
    final picked = await showModalBottomSheet<ServiceCatalogItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchPickerSheet<ServiceCatalogItem>(
        title: 'Tipo de consulta / servicio',
        items: services,
        labelOf: (s) => s.name,
        sublabelOf: (s) => _money(s.price),
      ),
    );
    if (picked != null) {
      setState(() => _lines.add(_ChargeLine(
            kind: 'servicio',
            name: picked.name,
            unitPrice: picked.price,
          )));
    }
  }

  Future<void> _addProducto() async {
    final items =
        widget.repo.listInventoryItems(organizationId: widget.orgId);
    if (items.isEmpty) {
      _snack('No hay productos en el inventario del centro.');
      return;
    }
    final picked = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchPickerSheet<InventoryItem>(
        title: 'Producto del inventario',
        items: items,
        labelOf: (i) => i.name,
        sublabelOf: (i) =>
            '${_money(i.unitPrice ?? i.unitCost ?? 0)} · stock ${widget.repo.onHandFor(i.id)}',
      ),
    );
    if (picked != null) {
      setState(() => _lines.add(_ChargeLine(
            kind: 'insumo',
            name: picked.name,
            unitPrice: picked.unitPrice ?? picked.unitCost ?? 0,
            inventoryItemId: picked.id,
          )));
    }
  }

  Future<void> _crear() async {
    if (widget.orgId == null) {
      _snack('Selecciona un centro para crear el cobro.');
      return;
    }
    if (_lines.isEmpty) {
      _snack('Agrega al menos un concepto.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repo.createManualCharge(
        organizationId: widget.orgId!,
        patientId: _patient?.id,
        siteId: null,
        lines: [
          for (final l in _lines)
            (
              kind: l.kind,
              name: l.name,
              quantity: l.quantity,
              unitPrice: l.unitPrice,
              inventoryItemId: l.inventoryItemId,
            ),
        ],
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('$e'.replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nuevo cobro',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 12),
            // Paciente (opcional)
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.person_outline,
                    color: _patient == null
                        ? KuraColors.darkText.withOpacity(0.5)
                        : KuraColors.primary),
                title: Text(_patient?.fullName ?? 'Venta de mostrador'),
                subtitle: Text(_patient == null
                    ? 'Sin paciente ligado (opcional)'
                    : _patient!.folio),
                trailing: _patient == null
                    ? TextButton(
                        onPressed: _pickPatient, child: const Text('Ligar'))
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _patient = null),
                      ),
                onTap: _pickPatient,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.medical_services_outlined, size: 18),
                    label: const Text('Servicio'),
                    onPressed: _busy ? null : _addServicio,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('Producto'),
                    onPressed: _busy ? null : _addProducto,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('Agrega servicios o productos al cobro.',
                      style: TextStyle(
                          color: KuraColors.darkText.withOpacity(0.5))),
                ),
              )
            else
              ...List.generate(_lines.length, (i) {
                final l = _lines[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        l.kind == 'servicio'
                            ? Icons.medical_services_outlined
                            : Icons.inventory_2_outlined,
                        size: 18,
                        color: KuraColors.darkText.withOpacity(0.6),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.name,
                                style: const TextStyle(fontSize: 13)),
                            Text(_money(l.unitPrice),
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        KuraColors.darkText.withOpacity(0.5))),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: () => setState(() {
                          if (l.quantity > 1) {
                            l.quantity--;
                          } else {
                            _lines.removeAt(i);
                          }
                        }),
                      ),
                      Text('${l.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () => setState(() => l.quantity++),
                      ),
                      SizedBox(
                        width: 72,
                        child: Text(_money(l.lineTotal),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                );
              }),
            const Divider(height: 24),
            Row(
              children: [
                const Expanded(
                    child: Text('Total',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16))),
                Text(_money(_total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_busy || _lines.isEmpty) ? null : _crear,
                child: Text(_busy ? 'Creando…' : 'Crear cobro'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja genérica de selección con buscador (paciente / servicio / producto).
class _SearchPickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T) sublabelOf;
  const _SearchPickerSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.sublabelOf,
  });
  @override
  State<_SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.items
        : widget.items
            .where((it) => widget.labelOf(it).toLowerCase().contains(q))
            .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar…',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Sin resultados.')),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final it = filtered[i];
                      return ListTile(
                        dense: true,
                        title: Text(widget.labelOf(it)),
                        subtitle: Text(widget.sublabelOf(it)),
                        onTap: () => Navigator.of(context).pop(it),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChargeDetailSheet extends StatefulWidget {
  final DataRepository repo;
  final Charge charge;
  const _ChargeDetailSheet({required this.repo, required this.charge});

  @override
  State<_ChargeDetailSheet> createState() => _ChargeDetailSheetState();
}

class _ChargeDetailSheetState extends State<_ChargeDetailSheet> {
  bool _busy = false;
  // Orden ya enviada a la terminal Point en esta sesión (revela Verificar/Cancelar
  // aunque el snapshot del cobro aún no refleje el proveedor).
  bool _sentToTerminal = false;

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final charge = widget.charge;
    final items = repo.listChargeItems(charge.id);
    final patient = charge.patientId == null ? null : repo.getPatient(charge.patientId!);
    // "Verificar pago (Point)" visible si el cobro ya está ligado a Mercado Pago
    // o si acabamos de enviar la orden a la terminal.
    final showVerify = charge.paymentProvider == 'mercadopago' || _sentToTerminal;
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
          if (charge.status == ChargeStatus.pendiente) ...[
            // Pago en línea (a distancia) = Stripe: genera un link para enviar
            // al paciente. Mercado Pago aquí es SOLO terminal Point (presencial);
            // "Cobrar con terminal (Point)" se agrega con la integración Point.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('Generar link de pago (Stripe)'),
                onPressed: _busy ? null : _generarLinkStripe,
              ),
            ),
            const SizedBox(height: 8),
            // Cobro presencial: envía la orden a la terminal Point (0074).
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Cobrar con terminal (Point)'),
                onPressed: _busy ? null : _cobrarConTerminal,
              ),
            ),
            const SizedBox(height: 8),
            if (_sentToTerminal)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KuraColors.infoBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Orden enviada a la terminal. Pídele al paciente que pague '
                  'en la terminal; luego toca "Verificar pago (Point)".',
                  style: TextStyle(
                      fontSize: 12, color: KuraColors.darkText.withOpacity(0.8)),
                ),
              ),
            if (showVerify) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: const Text('Verificar pago (Point)'),
                  onPressed: _busy ? null : _verificarPago,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_sentToTerminal) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cancel_schedule_send_outlined),
                  label: const Text('Cancelar orden en terminal'),
                  onPressed: _busy ? null : _cancelarOrdenTerminal,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await repo.cancelCharge(charge.id);
                          if (mounted) Navigator.of(context).pop();
                        },
                  child: const Text('Cancelar cobro'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final method = await _pickMethod(context);
                          if (method == null) return;
                          await repo.markChargePaid(charge.id, method);
                          if (mounted) Navigator.of(context).pop();
                        },
                  child: const Text('Registrar pago'),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  /// Envía la orden de cobro a la terminal Point (payment intent). La terminal
  /// pide la tarjeta; el pago se concilia por webhook/pull.
  Future<void> _cobrarConTerminal() async {
    final repo = widget.repo;
    final charge = widget.charge;
    final patient =
        charge.patientId == null ? null : repo.getPatient(charge.patientId!);
    setState(() => _busy = true);
    try {
      await repo.createPointIntent(
        charge.id,
        title: patient != null
            ? 'Cobro · ${patient.fullName}'
            : 'Cobro de consulta',
      );
      if (!mounted) return;
      setState(() => _sentToTerminal = true);
      _snack('Orden enviada a la terminal 🟢');
    } catch (e) {
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cancela la orden abierta en la terminal (si el paciente aún no pagó).
  Future<void> _cancelarOrdenTerminal() async {
    setState(() => _busy = true);
    try {
      await widget.repo.cancelPointIntent(widget.charge.id);
      if (!mounted) return;
      setState(() => _sentToTerminal = false);
      _snack('Orden cancelada en la terminal.');
    } catch (e) {
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Consulta a Mercado Pago el estado del pago (pull) y actualiza al instante.
  Future<void> _verificarPago() async {
    setState(() => _busy = true);
    try {
      final status = await widget.repo.syncMercadoPagoCharge(widget.charge.id);
      if (!mounted) return;
      if (status == 'pagado' || status == 'approved') {
        _snack('Pago confirmado ✅');
        Navigator.of(context).pop();
      } else if (status == 'sin_pago') {
        _snack('Aún no hay un pago registrado para este cobro.');
      } else {
        _snack('El pago está "$status". Aún no se acredita.');
      }
    } catch (e) {
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  /// Genera un link de pago de Stripe para el cobro y lo muestra para
  /// compartir con el paciente (copiar / WhatsApp). El pago se concilia solo.
  Future<void> _generarLinkStripe() async {
    final repo = widget.repo;
    final charge = widget.charge;
    final patient =
        charge.patientId == null ? null : repo.getPatient(charge.patientId!);
    setState(() => _busy = true);
    String? url;
    try {
      url = await repo.createStripeCheckout(
        charge.id,
        title: patient != null ? 'Cobro · ${patient.fullName}' : 'Cobro de consulta',
      );
    } catch (e) {
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (url == null || !mounted) return;
    final link = url;
    final saludo = patient != null ? ' ${patient.fullName.split(' ').first}' : '';
    final msg = 'Hola$saludo, aquí está tu link de pago: $link';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link de pago (Stripe)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Comparte este link con el paciente. Al pagar, el cobro se marca '
                'como pagado automáticamente.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            SelectableText(link, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiar'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              _snack('Link copiado.');
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: const Text('WhatsApp'),
            onPressed: () => launchUrl(
              Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}'),
              mode: LaunchMode.externalApplication,
              webOnlyWindowName: '_blank',
            ),
          ),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar')),
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
    // Si el centro tiene Acuity integrado, el catálogo es el de Acuity (tipos de
    // cita con su precio) — se administra allá; aquí es de solo lectura.
    if (repo.schedulingModeFor(widget.orgId) == 'acuity') {
      return _acuityView(context);
    }
    return _localView(context, repo);
  }

  /// Catálogo LOCAL de servicios (centros sin Acuity): CRUD de honorarios.
  Widget _localView(BuildContext context, DataRepository repo) {
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
              // Clearance de la barra flotante del shell + el FAB de esta
              // pestaña, para que el último servicio no quede tapado en móvil.
              padding: EdgeInsets.fromLTRB(16, 12, 16,
                  MediaQuery.of(context).viewPadding.bottom +
                      kFloatingNavBarHeight +
                      80),
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

  /// Catálogo tomado de Acuity (tipos de cita con su precio). Solo lectura: el
  /// alta/edición/precio se administra en Acuity y aquí se refleja en vivo.
  Widget _acuityView(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: ref.read(acuityServiceProvider).appointmentTypes(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se pudo cargar el catálogo de Acuity.\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: KuraColors.darkText),
              ),
            ),
          );
        }
        final types = (snap.data ?? const []).whereType<Map>().toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KuraColors.infoBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync, size: 18, color: KuraColors.infoBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Catálogo sincronizado con Acuity. Los servicios y sus '
                      'precios se administran en Acuity; aquí se muestran en vivo.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (types.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Acuity no devolvió tipos de cita.')),
              )
            else
              for (final t in types)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available_outlined,
                      color: KuraColors.primary),
                  title: Text('${t['name'] ?? ''}',
                      style: TextStyle(
                          decoration: t['active'] == false
                              ? TextDecoration.lineThrough
                              : null)),
                  subtitle: Text([
                    _money(double.tryParse('${t['price'] ?? ''}') ?? 0),
                    if (t['duration'] != null) '${t['duration']} min',
                    if ('${t['category'] ?? ''}'.isNotEmpty) '${t['category']}',
                  ].join(' · ')),
                ),
          ],
        );
      },
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
  final void Function(int) onOpenSection;
  const _ResumenTab(
      {required this.repo, required this.orgId, required this.onOpenSection});

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
          onTap: () => onOpenSection(1),
        ),
        _ProcessCard(
          icon: Icons.sync_alt_outlined,
          title: 'Conciliación',
          subtitle: 'Pagos de terminal (Point) ligados al cobro del paciente.',
          onTap: () => onOpenSection(2),
        ),
        _ProcessCard(
          icon: Icons.sell_outlined,
          title: 'Servicios',
          subtitle: 'Catálogo de honorarios del centro.',
          onTap: () => onOpenSection(3),
        ),
        _ProcessCard(
          icon: Icons.inventory_outlined,
          title: 'Reserva de stock (mes)',
          subtitle:
              'Explosión de materiales de los planes aceptados vs. stock.',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const MaterialsExplosionScreen())),
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

String _methodLabel(String? m) => switch (m) {
      'credit_card' => 'Tarjeta de crédito',
      'debit_card' => 'Tarjeta de débito',
      'efectivo' => 'Efectivo',
      'transferencia' => 'Transferencia',
      null => 'Terminal',
      _ => m,
    };

/// Config de la terminal Mercado Pago Point del centro (0074). Muestra la
/// terminal asignada y permite elegirla de la lista de dispositivos de la cuenta.
class _TerminalConfigCard extends StatefulWidget {
  final DataRepository repo;
  final String? orgId;
  final String? deviceId;
  final VoidCallback onChanged;
  const _TerminalConfigCard({
    required this.repo,
    required this.orgId,
    required this.deviceId,
    required this.onChanged,
  });
  @override
  State<_TerminalConfigCard> createState() => _TerminalConfigCardState();
}

class _TerminalConfigCardState extends State<_TerminalConfigCard> {
  bool _busy = false;

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _configurar() async {
    if (widget.orgId == null) return;
    setState(() => _busy = true);
    List<Map<String, dynamic>> devices;
    String mode;
    try {
      final res = await widget.repo.listPointDevices();
      devices = res.devices;
      mode = res.mode;
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('$e'.replaceFirst('Exception: ', ''));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (devices.isEmpty) {
      final hint = mode == 'prod'
          ? 'La cuenta de producción no tiene terminales encendidas/vinculadas. '
              'Enciende la terminal y verifica que esté asociada a esta cuenta.'
          : 'La función está en modo PRUEBA (MP_MODE=test), que no ve terminales '
              'reales. Configura MP_MODE=prod y el token de producción en Supabase.';
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Sin terminales (modo: $mode)'),
          content: Text('No se encontraron terminales Point.\n\n$hint'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido')),
          ],
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Elige la terminal del centro',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            for (final d in devices)
              ListTile(
                leading: const Icon(Icons.point_of_sale),
                title: Text('${d['id']}'),
                subtitle: Text(
                    'Modo: ${d['operating_mode'] ?? '—'}'
                    '${widget.deviceId == d['id'] ? ' · (actual)' : ''}'),
                onTap: () => Navigator.of(context).pop('${d['id']}'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      await widget.repo.setOrgPointDevice(widget.orgId!, picked);
      // Asegura modo integrado (PDV) para que reciba órdenes.
      try {
        await widget.repo.setPointDevicePdv(picked);
      } catch (_) {/* no bloquea: puede ya estar en PDV */}
      if (mounted) _snack('Terminal configurada ✅');
      widget.onChanged();
    } catch (e) {
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = (widget.deviceId ?? '').isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Icon(Icons.point_of_sale,
                color: configured ? KuraColors.success : KuraColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Terminal Point',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    configured
                        ? 'Asignada: ${widget.deviceId}'
                        : 'Sin terminal configurada.',
                    style: TextStyle(
                        fontSize: 12,
                        color: KuraColors.darkText.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
            _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: _configurar,
                    child: Text(configured ? 'Cambiar' : 'Configurar'),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Conciliación: bandeja de pagos de terminal (Mercado Pago Point). Los sin
/// ligar se concilian a mano; en Fase 2 el webhook los liga automáticamente por
/// la referencia (folio del paciente / consulta).
class _ConciliacionTab extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? orgId;
  const _ConciliacionTab({required this.repo, required this.orgId});
  @override
  ConsumerState<_ConciliacionTab> createState() => _ConciliacionTabState();
}

class _ConciliacionTabState extends ConsumerState<_ConciliacionTab> {
  final _fmt = DateFormat('dd/MM/yyyy HH:mm');
  Object? _subPayments;
  Object? _subCharges;

  @override
  void initState() {
    super.initState();
    // Realtime: un pago nuevo (point_payments) o un cambio de vínculo/estado en
    // el cobro (charges) se refleja al instante en la bandeja de conciliación.
    void refresh() {
      if (mounted) setState(() {});
    }

    _subPayments = widget.repo.watchCollection('point_payments', refresh);
    _subCharges = widget.repo.watchCollection('charges', refresh);
  }

  @override
  void dispose() {
    widget.repo.unwatch(_subPayments);
    widget.repo.unwatch(_subCharges);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    // Excluye las órdenes de terminal (intents): son seguimiento del push, no
    // pagos a conciliar; el pago real llega como fila propia (webhook/pull).
    final all = repo
        .listPointPayments(organizationId: widget.orgId)
        .where((p) => p.source != 'point_intent')
        .toList();
    final unlinked = all.where((p) => !p.isLinked).toList();
    final linked = all.where((p) => p.isLinked).toList();
    final unlinkedTotal = unlinked.fold<double>(0, (a, p) => a + p.amount);

    final org = repo.organizationById(widget.orgId);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          _TerminalConfigCard(
            repo: repo,
            orgId: widget.orgId,
            deviceId: org?.mpPointDeviceId,
            onChanged: () {
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _KpiBox(
                    label: 'Sin ligar',
                    value: '${unlinked.length}',
                    color: KuraColors.warning)),
            const SizedBox(width: 10),
            Expanded(
                child: _KpiBox(
                    label: 'Monto sin ligar',
                    value: _money(unlinkedTotal),
                    color: KuraColors.warning)),
          ]),
          const SizedBox(height: 10),
          Text(
              'La terminal envía el pago con una referencia (folio del paciente / '
              'consulta) para ligarlo automáticamente al cobro. Mientras tanto, '
              'los pagos sin ligar se concilian a mano aquí.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Sin pagos de terminal registrados.')),
            )
          else ...[
            if (unlinked.isNotEmpty) ...[
              const _SectionLabel('Sin ligar'),
              ...unlinked.map((p) => _PaymentCard(
                    payment: p,
                    repo: repo,
                    fmt: _fmt,
                    onLink: () => _link(repo, p),
                    onUnlink: null,
                  )),
              const SizedBox(height: 12),
            ],
            if (linked.isNotEmpty) ...[
              const _SectionLabel('Ligados'),
              ...linked.map((p) => _PaymentCard(
                    payment: p,
                    repo: repo,
                    fmt: _fmt,
                    onLink: null,
                    onUnlink: () async {
                      await repo.unlinkPointPayment(p.id);
                      if (mounted) setState(() {});
                    },
                  )),
            ],
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addManual(repo),
        icon: const Icon(Icons.add_card),
        label: const Text('Registrar pago'),
      ),
    );
  }

  Future<void> _link(DataRepository repo, PointPayment p) async {
    final charges = repo.listCharges(
        organizationId: widget.orgId, status: ChargeStatus.pendiente);
    if (charges.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay cobros pendientes para ligar.')));
      return;
    }
    // Sugerencia: primero los cobros cuyo folio de paciente == referencia del
    // pago, luego los que calzan por monto.
    int rank(Charge c) {
      final folio =
          c.patientId == null ? null : repo.getPatient(c.patientId!)?.folio;
      final refMatch =
          p.externalReference != null && folio == p.externalReference;
      final amtMatch = (c.total - p.amount).abs() < 0.01;
      return (refMatch ? 0 : 2) + (amtMatch ? 0 : 1);
    }

    final sorted = [...charges]..sort((a, b) => rank(a).compareTo(rank(b)));
    final chosen = await showModalBottomSheet<Charge>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Ligar a cobro pendiente',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in sorted)
                    ListTile(
                      title: Text(c.patientId == null
                          ? 'Paciente'
                          : (repo.getPatient(c.patientId!)?.fullName ??
                              'Paciente')),
                      subtitle: Text(c.patientId == null
                          ? ''
                          : (repo.getPatient(c.patientId!)?.folio ?? '')),
                      trailing: Text(_money(c.total),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: (c.total - p.amount).abs() < 0.01
                                  ? KuraColors.success
                                  : null)),
                      onTap: () => Navigator.of(ctx).pop(c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await repo.linkPointPaymentToCharge(
        paymentId: p.id,
        chargeId: chosen.id,
        linkedBy: ref.read(sessionProvider).user?.id);
    if (mounted) setState(() {});
  }

  Future<void> _addManual(DataRepository repo) async {
    if (widget.orgId == null) return;
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    var method = 'credit_card';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Registrar pago de terminal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto (MXN) *'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: method,
                decoration: const InputDecoration(labelText: 'Método'),
                items: const [
                  DropdownMenuItem(
                      value: 'credit_card', child: Text('Tarjeta de crédito')),
                  DropdownMenuItem(
                      value: 'debit_card', child: Text('Tarjeta de débito')),
                  DropdownMenuItem(value: 'other', child: Text('Otro')),
                ],
                onChanged: (v) => setSt(() => method = v ?? 'credit_card'),
              ),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                    labelText: 'Referencia (folio del paciente, opcional)'),
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
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) return;
    final refText = refCtrl.text.trim();
    await repo.addPointPayment(
      organizationId: widget.orgId!,
      amount: amount,
      method: method,
      externalReference: refText.isEmpty ? null : refText,
      description: 'Registrado manualmente',
      createdBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) setState(() {});
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: KuraColors.darkText.withValues(alpha: 0.6))),
      );
}

class _PaymentCard extends StatelessWidget {
  final PointPayment payment;
  final DataRepository repo;
  final DateFormat fmt;
  final VoidCallback? onLink;
  final Future<void> Function()? onUnlink;
  const _PaymentCard({
    required this.payment,
    required this.repo,
    required this.fmt,
    required this.onLink,
    required this.onUnlink,
  });

  @override
  Widget build(BuildContext context) {
    final p = payment;
    // Paciente ligado (si aplica): se busca el cobro en la lista del centro.
    String? linkedPatient;
    if (p.chargeId != null) {
      final charge = repo
          .listCharges(organizationId: p.organizationId)
          .where((c) => c.id == p.chargeId);
      if (charge.isNotEmpty && charge.first.patientId != null) {
        linkedPatient = repo.getPatient(charge.first.patientId!)?.fullName;
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.point_of_sale,
                color: p.isLinked ? KuraColors.success : KuraColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_money(p.amount),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    [
                      p.providerLabel,
                      _methodLabel(p.method),
                      fmt.format(p.capturedAt ?? p.createdAt),
                      if (p.externalReference != null)
                        'Ref: ${p.externalReference}',
                      if (linkedPatient != null) '→ $linkedPatient',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onLink != null)
              FilledButton(onPressed: onLink, child: const Text('Ligar'))
            else if (onUnlink != null)
              TextButton(
                  onPressed: () => onUnlink!(), child: const Text('Desligar')),
          ],
        ),
      ),
    );
  }
}

/// Facturación: placeholder — requiere integrar un PAC/facturador.
class _FacturacionTab extends StatelessWidget {
  const _FacturacionTab();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 44, color: KuraColors.darkText.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              const Text('Facturación (CFDI)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'Pendiente de integrar un PAC/facturador. Los datos del pago '
                '(monto, método, referencia) ya quedan registrados en Cobros y '
                'Conciliación para alimentar la factura cuando se conecte.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
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
