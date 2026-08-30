import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/inventory.dart';
import '../../services/data_repository.dart';
import 'dashboard_charts.dart';
import 'purchase_guard.dart';

/// Módulo de Insumos (clínica de heridas): tienda de productos de heridas
/// (Shopify) + —con licencia premium— mapeo insumo↔producto, inventario, costeo
/// por paciente y reabasto. Esta pantalla es la portada del módulo: muestra las
/// secciones y su estado (disponible / premium / próximamente). Se entrega por
/// fases; aquí se arma el andamiaje y el gating.
class InsumosHomeScreen extends ConsumerWidget {
  const InsumosHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insumos'),
        actions: const [UserMenuButton()],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final premium = repo.premiumInsumosFor(user?.organizationId);
          // La compra es del admin del centro (y master); enfermería/clínico no
          // ven tienda/inventario/reabasto/mapeo. Consumo (clínico) sí queda.
          final canPurchase = canPurchaseSupplies(user);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text('Insumos y tienda',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Adquiere productos de heridas de tu tienda en línea y —con la '
                'licencia premium— gestiona su mapeo al protocolo, inventario, '
                'costeo por paciente y reabasto.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              _LicenseBanner(premium: premium),
              const SizedBox(height: 12),

              // Dashboard: gráficos (solo con datos/premium).
              if (premium) ..._insumosCharts(repo, user?.organizationId),

              // Base (no premium) — YA disponible. Solo compradores (admin/master).
              if (canPurchase)
                _SectionCard(
                  icon: Icons.storefront_outlined,
                  title: 'Tienda',
                  subtitle:
                      'Catálogo de productos de heridas y compra con checkout seguro.',
                  status: _Status.disponible,
                  phase: 'Fase 1',
                  onTap: () => context.go('/insumos/tienda'),
                ),

              // Premium — Mapeo YA disponible (Fase 2) cuando hay licencia.
              if (canPurchase)
                _SectionCard(
                  icon: Icons.link_outlined,
                  title: 'Mapeo insumo ↔ producto',
                  subtitle:
                      'Liga cada insumo del protocolo a un producto concreto '
                      '(p. ej. Apósito de espuma → Mepilex Border).',
                  status: premium ? _Status.disponible : _Status.premium,
                  phase: 'Fase 2',
                  onTap: premium ? () => context.go('/insumos/mapeo') : null,
                ),
              if (canPurchase)
                _SectionCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Inventario',
                  subtitle: 'Existencias por sitio con entradas, salidas y ajustes.',
                  status: premium ? _Status.disponible : _Status.premium,
                  phase: 'Fase 3',
                  onTap: premium ? () => context.go('/insumos/inventario') : null,
                ),
              _SectionCard(
                icon: Icons.receipt_long_outlined,
                title: 'Consumo y costeo por paciente',
                subtitle:
                    'Insumos usados por tratamiento, costo por paciente y '
                    'trazabilidad del consumo.',
                status: premium ? _Status.disponible : _Status.premium,
                phase: 'Fase 4',
                onTap: premium ? () => context.go('/insumos/consumo') : null,
              ),
              if (canPurchase)
                _SectionCard(
                  icon: Icons.autorenew_outlined,
                  title: 'Reabasto sugerido',
                  subtitle:
                      'Artículos bajo su umbral → carrito de reorden en tu tienda.',
                  status: premium ? _Status.disponible : _Status.premium,
                  phase: 'Fase 5',
                  onTap: premium ? () => context.go('/insumos/reabasto') : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

enum _Status { disponible, pronto, premium }

class _LicenseBanner extends StatelessWidget {
  final bool premium;
  const _LicenseBanner({required this.premium});

  @override
  Widget build(BuildContext context) {
    final color = premium ? KuraColors.success : KuraColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(premium ? Icons.verified_outlined : Icons.workspace_premium_outlined,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              premium
                  ? 'Licencia premium activa: las funciones avanzadas están disponibles para este centro.'
                  : 'Sin licencia premium: solo la tienda base. Solicita la licencia a tu administrador de plataforma para el mapeo, inventario, costeo y reabasto.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final _Status status;
  final String phase;
  final VoidCallback? onTap;
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.phase,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPremiumLocked = status == _Status.premium;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: isPremiumLocked ? KuraColors.darkText : KuraColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      _StatusChip(status: status, phase: phase),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final _Status status;
  final String phase;
  const _StatusChip({required this.status, required this.phase});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      _Status.disponible => ('Disponible', KuraColors.success, Icons.check_circle_outline),
      _Status.pronto => ('Próximamente · $phase', KuraColors.primary, Icons.schedule),
      _Status.premium => ('Premium · $phase', KuraColors.warning, Icons.lock_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Gráficos del dashboard de Insumos: estado del inventario (dona) + consumo
/// mensual (barras), agregados a nivel centro.
List<Widget> _insumosCharts(DataRepository repo, String? orgId) {
  final items = repo.listInventoryItems(organizationId: orgId);
  var ok = 0, low = 0, out = 0;
  for (final it in items) {
    final oh = repo.onHandFor(it.id);
    if (oh <= 0) {
      out++;
    } else if (it.reorderThreshold != null && oh <= it.reorderThreshold!) {
      low++;
    } else {
      ok++;
    }
  }

  return [
    DonutCard(title: 'Estado del inventario', slices: [
      DonutSlice('Con stock', ok.toDouble(), KuraColors.success),
      DonutSlice('Por reordenar', low.toDouble(), KuraColors.warning),
      DonutSlice('Agotado', out.toDouble(), KuraColors.danger),
    ]),
    const SizedBox(height: 12),
    _ConsumoChartCard(repo: repo, orgId: orgId),
    const SizedBox(height: 16),
  ];
}

/// Gráfico "Consumo por mes" con filtro por producto (Todos o un insumo).
class _ConsumoChartCard extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? orgId;
  const _ConsumoChartCard({required this.repo, required this.orgId});
  @override
  ConsumerState<_ConsumoChartCard> createState() => _ConsumoChartCardState();
}

class _ConsumoChartCardState extends ConsumerState<_ConsumoChartCard> {
  String? _productId; // null = todos

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final consumo = repo
        .listInventoryMovements(organizationId: widget.orgId)
        .where((m) => m.reason == InventoryReason.consumo)
        .toList();
    final nameById = {
      for (final it in repo.listInventoryItems(
          organizationId: widget.orgId, activeOnly: false))
        it.id: it.name
    };
    final productIds = consumo
        .map((m) => m.inventoryItemId)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort((a, b) => (nameById[a] ?? '').compareTo(nameById[b] ?? ''));
    if (_productId != null && !productIds.contains(_productId)) _productId = null;

    final filtered = _productId == null
        ? consumo
        : consumo.where((m) => m.inventoryItemId == _productId).toList();

    final now = DateTime.now();
    final months = <MonthValue>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final next = DateTime(m.year, m.month + 1, 1);
      final qty = filtered
          .where((x) => !x.createdAt.isBefore(m) && x.createdAt.isBefore(next))
          .fold<double>(0, (a, x) => a + x.delta.abs());
      months.add(MonthValue(kMonthShort[m.month - 1], qty));
    }

    return MonthlyBarChart(
      title: 'Consumo por mes (piezas)',
      data: months,
      headerTrailing: productIds.isEmpty
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: DropdownButton<String?>(
                value: _productId,
                isExpanded: true,
                isDense: true,
                underline: const SizedBox.shrink(),
                hint: const Text('Producto', style: TextStyle(fontSize: 12)),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Todos', style: TextStyle(fontSize: 12))),
                  for (final id in productIds)
                    DropdownMenuItem<String?>(
                        value: id,
                        child: Text(nameById[id] ?? 'Producto',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12))),
                ],
                onChanged: (v) => setState(() => _productId = v),
              ),
            ),
    );
  }
}
