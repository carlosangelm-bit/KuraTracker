import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;

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
              const SizedBox(height: 8),

              // Base (no premium) — YA disponible.
              _SectionCard(
                icon: Icons.storefront_outlined,
                title: 'Tienda',
                subtitle:
                    'Catálogo de productos de heridas y compra con checkout seguro.',
                status: _Status.disponible,
                phase: 'Fase 1',
                onTap: () => context.go('/insumos/tienda'),
              ),

              // Premium.
              _SectionCard(
                icon: Icons.link_outlined,
                title: 'Mapeo insumo ↔ producto',
                subtitle:
                    'Liga cada insumo del protocolo a un producto concreto '
                    '(p. ej. Apósito de espuma → Mepilex Border).',
                status: premium ? _Status.pronto : _Status.premium,
                phase: 'Fase 2',
              ),
              _SectionCard(
                icon: Icons.inventory_2_outlined,
                title: 'Inventario',
                subtitle: 'Existencias por centro/sitio con entradas y salidas.',
                status: premium ? _Status.pronto : _Status.premium,
                phase: 'Fase 3',
              ),
              _SectionCard(
                icon: Icons.receipt_long_outlined,
                title: 'Consumo y costeo por paciente',
                subtitle:
                    'Insumos usados por tratamiento, costo por paciente y '
                    'trazabilidad del consumo.',
                status: premium ? _Status.pronto : _Status.premium,
                phase: 'Fase 4',
              ),
              _SectionCard(
                icon: Icons.autorenew_outlined,
                title: 'Reabasto sugerido',
                subtitle:
                    'Sugerencias de reorden según el consumo y las existencias.',
                status: premium ? _Status.pronto : _Status.premium,
                phase: 'Fase 5',
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
