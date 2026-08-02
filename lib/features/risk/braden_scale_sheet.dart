import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/risk/braden_scale.dart';

/// Sheet de la **escala de Braden completa** (6 subescalas): el profesional
/// elige una opción por ítem y la app calcula el total y la banda de riesgo.
/// Devuelve `(total, subescalas, notas)` o `null` si se cancela.
///
/// UI compartida entre el módulo de prevención ([_assessBraden] en
/// patient_risk_screen) y la valoración de heridas (wound_capture), para no
/// duplicar la escala ni forzar puntajes "a ojo".
Future<({int total, Map<String, int> subscores, String? notes})?>
    showBradenScaleSheet(BuildContext context, BradenScale scale) async {
  final selections = <String, int>{};
  final notesCtrl = TextEditingController();

  final result = await showModalBottomSheet<Map<String, int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final answered = selections.length == scale.items.length;
        final total = selections.values.fold<int>(0, (a, b) => a + b);
        final band = answered ? scale.riskLabelFor(total) : null;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Valoración de Braden',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text('Elige una opción por ítem; el total se calcula solo.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in scale.items) ...[
                          Text(item.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final o in item.options)
                                ChoiceChip(
                                  label: Text('${o.score} · ${o.label}',
                                      style: const TextStyle(fontSize: 12)),
                                  selected: selections[item.id] == o.score,
                                  selectedColor:
                                      KuraColors.primary.withOpacity(0.16),
                                  onSelected: (_) => setSheet(
                                      () => selections[item.id] = o.score),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Notas (opcional)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        answered
                            ? 'Total: $total  ·  ${band ?? ''}'
                            : 'Faltan ${scale.items.length - selections.length} ítem(s)',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: answered
                                ? KuraColors.primary
                                : KuraColors.darkText.withOpacity(0.6)),
                      ),
                    ),
                    FilledButton(
                      onPressed: answered
                          ? () => Navigator.of(ctx)
                              .pop(Map<String, int>.from(selections))
                          : null,
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  if (result == null) return null;
  final total = result.values.fold<int>(0, (a, b) => a + b);
  final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
  return (total: total, subscores: result, notes: notes);
}
