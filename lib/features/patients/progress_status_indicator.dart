import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/sheehan_decision_style.dart';
import 'patient_progress_status.dart';

/// Indicador visual del semaforo de avance (punto 3 del rediseno):
/// punto/franja de color + icono + etiqueta corta -- nunca solo color, por
/// accesibilidad/daltonismo -- con Tooltip que explica el estatus (incluye
/// el detalle por herida cuando el paciente tiene mas de una activa).
/// Compartido por [PatientListTile] y [PatientGridCard] para que ambas
/// vistas se vean IDENTICAS frente al mismo semaforo.
class ProgressStatusIndicator extends StatelessWidget {
  final PatientProgressStatus status;
  const ProgressStatusIndicator({super.key, required this.status});

  String _tooltipMessage() {
    if (status.byWound.isEmpty) {
      return status.worst.tooltip();
    }
    if (status.byWound.length == 1) {
      final only = status.byWound.first;
      return only.status.tooltip(checkpoint: only.checkpoint);
    }
    // Varias heridas activas: se lista el estatus de cada una (punto 2 del
    // rediseno: "un tooltip puede listar el estatus por herida").
    final lines = status.byWound
        .map((w) => '• ${w.wound.etiology.label}: ${w.status.shortLabel}')
        .join('\n');
    return 'Peor estatus mostrado (de ${status.byWound.length} heridas activas):\n$lines';
  }

  @override
  Widget build(BuildContext context) {
    final style = status.worst;
    return Tooltip(
      message: _tooltipMessage(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: style.color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: style.color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 14, color: style.color),
            const SizedBox(width: 4),
            Text(
              style.shortLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: style.color == KuraColors.warning
                    ? KuraColors.darkText // texto oscuro sobre amarillo: contraste
                    : style.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
