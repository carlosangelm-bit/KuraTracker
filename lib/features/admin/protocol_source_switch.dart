import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../services/data_repository.dart';

/// El INTERRUPTOR de la fuente del protocolo del centro (spec 19-sep), CABLEADO UNA VEZ para las
/// dos caras de la Matriz: la del catálogo Kura+ y la del editor de reglas propias. Antes solo se
/// dibujaba `if (isMaster)`; ahora lo ve y acciona también el admin del centro (la pantalla ya
/// vive detrás de module:admin, y el RPC/trigger respaldan la autoridad: master, o admin del
/// centro con module:admin sobre su propio centro).
///
/// Con [editingOwnMatrix] en true (cara del editor propio), si el centro HOY resuelve con Kura+
/// se muestra un aviso: se está editando una matriz que no se está aplicando — justo lo que
/// pasaba a ciegas antes.
class ProtocolSourceSwitch extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  final bool editingOwnMatrix;
  const ProtocolSourceSwitch({
    super.key,
    required this.repo,
    required this.organizationId,
    this.editingOwnMatrix = false,
  });

  @override
  ConsumerState<ProtocolSourceSwitch> createState() =>
      _ProtocolSourceSwitchState();
}

class _ProtocolSourceSwitchState extends ConsumerState<ProtocolSourceSwitch> {
  bool? _override; // reflejo instantáneo tras accionar, antes de refrescar la caché
  bool _flipping = false;

  bool get _catalog =>
      _override ?? widget.repo.resolvesFromCatalog(widget.organizationId);

  Future<void> _flip(bool on) async {
    final org = widget.organizationId;
    if (org == null) return;
    setState(() => _flipping = true);
    try {
      await widget.repo.setOrgResolvesFromCatalog(org, on);
      if (!mounted) return;
      setState(() {
        _override = on;
        _flipping = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(on
              ? 'Ahora el centro resuelve con la matriz de Kura+.'
              : 'Ahora el centro resuelve con sus reglas propias.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _flipping = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo cambiar la fuente: '
              '${'$e'.replaceFirst('Exception: ', '')}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final catalog = _catalog;
    final color = catalog ? t.brandPrimary : t.statusWarning;
    // Aviso de "editas a ciegas": en el editor propio, cuando hoy resuelve con Kura+.
    final blindEdit = widget.editingOwnMatrix && catalog;
    return Card(
      color: (blindEdit ? t.statusWarning : color).withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(catalog ? Icons.verified : Icons.folder_outlined,
                    size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Este centro resuelve el protocolo con:',
                          style: TextStyle(fontSize: 12)),
                      Text(
                        catalog
                            ? 'La matriz de Kura+'
                            : 'La matriz propia del centro',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: color),
                      ),
                    ],
                  ),
                ),
                _flipping
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Switch(value: catalog, onChanged: _flip),
              ],
            ),
            const SizedBox(height: 4),
            if (blindEdit)
              Text(
                'Estás editando tu matriz, pero HOY el centro resuelve con Kura+: '
                'lo que captures aquí no se está aplicando. Apaga el interruptor '
                'para usar tus reglas.',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: t.statusWarning),
              )
            else
              Text(
                catalog
                    ? 'Cámbialo para resolver con las reglas propias del centro.'
                    : 'Cámbialo para resolver con la matriz de Kura+ (no necesitas '
                        'capturar reglas).',
                style: TextStyle(fontSize: 11, color: t.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
