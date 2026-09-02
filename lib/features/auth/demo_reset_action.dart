import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../services/data_repository.dart';
import '../../services/demo/demo_lead_service.dart';

/// Reinicia la demo entre un prospecto y el siguiente. Único flujo para las tres
/// entradas (el botón del selector y los dos menús de usuario). Es destructivo →
/// confirma primero. Restaura los datos sembrados, limpia los filtros/vista
/// persistidos (resetDemoData → resetAndReseed) y borra el LEAD ACTIVO para que
/// el siguiente vea el formulario en blanco y el dashboard no salude con el
/// nombre del anterior. NO borra la cola de leads pendientes de enviar (§5.4/§7).
///
/// Termina en `/demo`, que al no haber lead vuelve a mostrar el formulario.
Future<void> showResetDemoDialog(BuildContext context, WidgetRef ref) async {
  final pending = await DemoLeadService.pending();
  if (!context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Reiniciar demo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Se borrarán los cambios de esta sesión de demostración y se '
              'restaurarán los datos de ejemplo.'),
          if (pending > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$pending lead(s) pendientes de enviar. No se borran: se '
              'reintentan cuando haya conexión.',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: KuraColors.warning),
            ),
            const SizedBox(height: 4),
            _CopyPendingCsvButton(),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
          onPressed: () => Navigator.pop(d, true),
          child: const Text('Reiniciar'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final repo = await DataRepository.instance();
  await repo.resetDemoData();
  await DemoLeadService.clearActiveLead();
  if (!context.mounted) return;
  context.go('/demo');
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Demo reiniciada · datos de ejemplo restaurados.')));
}

/// Copia los leads pendientes al portapapeles como CSV, para no perder ninguno
/// si la red falló todo el evento. Dentro del diálogo de reinicio; da feedback
/// "Copiado" sin cerrar el diálogo.
class _CopyPendingCsvButton extends StatefulWidget {
  @override
  State<_CopyPendingCsvButton> createState() => _CopyPendingCsvButtonState();
}

class _CopyPendingCsvButtonState extends State<_CopyPendingCsvButton> {
  bool _copied = false;

  Future<void> _copy() async {
    final csv = await DemoLeadService.pendingAsCsv();
    if (csv.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _copied ? null : _copy,
        icon: Icon(_copied ? Icons.check : Icons.copy_all_outlined, size: 18),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: KuraColors.primary),
        label: Text(_copied ? 'Copiado ✓' : 'Copiar pendientes (CSV)'),
      ),
    );
  }
}
