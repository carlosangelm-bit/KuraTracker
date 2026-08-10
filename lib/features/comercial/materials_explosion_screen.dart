import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';

/// Explosión de materiales del mes (reserva de stock). Agrega los insumos de
/// todos los planes de tratamiento ACEPTADOS del centro y los compara con el
/// stock actual, para que atención a cliente reserve/compre lo faltante.
class MaterialsExplosionScreen extends ConsumerWidget {
  const MaterialsExplosionScreen({super.key});

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;
    final orgId = ref.watch(sessionProvider).user?.organizationId;
    return Scaffold(
      appBar: AppBar(title: const Text('Reserva de stock (mes)')),
      body: (repo == null || orgId == null)
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              final rows = repo.centerMaterialsExplosion(orgId);
              if (rows.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Sin planes de tratamiento aceptados. La explosión de '
                      'materiales aparece cuando hay planes activos.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  Text(
                    'Total de insumos requeridos este mes por los planes '
                    'aceptados, comparado con el stock actual. El faltante es lo '
                    'que hay que reservar/comprar.',
                    style: TextStyle(
                        fontSize: 12,
                        color: KuraColors.darkText.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                          flex: 4,
                          child: Text('Producto',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 12))),
                      _hdr('Necesita'),
                      _hdr('Stock'),
                      _hdr('Faltante'),
                    ],
                  ),
                  const Divider(),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 4,
                              child: Text(r.name,
                                  style: const TextStyle(fontSize: 13))),
                          _cell(_fmt(r.needed)),
                          _cell('${r.onHand}'),
                          _cell(
                            _fmt((r.needed - r.onHand).clamp(0, double.infinity)),
                            danger: r.needed > r.onHand,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }),
    );
  }

  Widget _hdr(String t) => Expanded(
        flex: 2,
        child: Text(t,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      );

  Widget _cell(String t, {bool danger = false}) => Expanded(
        flex: 2,
        child: Text(t,
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 13,
                fontWeight: danger ? FontWeight.w800 : FontWeight.w500,
                color: danger ? KuraColors.danger : null)),
      );
}
