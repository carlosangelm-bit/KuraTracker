import 'package:flutter/material.dart';

import '../design/tints.dart';
import '../design/tokens.dart';

/// Tono de una cifra: normal, o de alarma cuando pide acción.
enum KuraStatTone { normal, warning, danger }

/// Cifra con contexto (canvas §6). Siempre tres piezas: etiqueta, cifra (con su
/// unidad pegada) y la línea de "qué significa" (periodo, fórmula, comparación).
/// Ninguna cifra se queda sola. En variante de alarma, borde/fondo teñidos y los
/// tres textos en el tono oscuro del estado. Todo color sale de [BrandTokens].
class KuraStat extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String meaning;
  final KuraStatTone tone;

  const KuraStat({
    super.key,
    required this.label,
    required this.value,
    required this.meaning,
    this.unit,
    this.tone = KuraStatTone.normal,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final alarm = tone != KuraStatTone.normal;
    final state = tone == KuraStatTone.danger ? t.statusDanger : t.statusWarning;

    final bg = alarm ? Tints.status(state, t.surface, 0.06) : t.surface;
    final borderColor = alarm ? Tints.statusBorder(state, t.surface, 0.32) : t.border;
    // Tonos oscuros del estado para el texto de alarma; en normal, la jerarquía
    // habitual de texto.
    final strong = alarm ? Tints.darkTone(t, state, 0.60) : t.textPrimary;
    final soft = alarm ? Tints.darkTone(t, state, 0.42) : t.textSecondary;
    final faint = alarm ? Tints.darkTone(t, state, 0.42) : t.textDisabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.mdR,
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: AppType.caption,
                fontWeight: AppType.bold,
                color: soft),
          ),
          const SizedBox(height: AppSpacing.xs + 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                    fontSize: AppType.display, // 28
                    fontWeight: AppType.extrabold,
                    letterSpacing: -0.02 * AppType.display,
                    height: 1.1,
                    color: strong),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppType.bold,
                      color: faint),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs + 1),
          Text(
            meaning,
            style: TextStyle(fontSize: AppType.caption, color: faint),
          ),
        ],
      ),
    );
  }
}
