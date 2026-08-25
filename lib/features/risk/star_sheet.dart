import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';

/// Sheet de la escala **STAR** (Skin Tear Audit Research): categoría por
/// realineación del colgajo + color. Dos modos: REALIZAR (elegir realineación +
/// color → 1a/1b/2a/2b/3) o CAPTURAR el resultado manualmente. Devuelve
/// `(category, subscores, notes)` o null si se cancela.
Future<({String category, Map<String, dynamic> subscores, String? notes})?>
    showStarSheet(BuildContext context) async {
  var manual = false;
  String? realineacion; // SIN_TENSION | NO_COMPLETA | AUSENTE
  String? color; // NORMAL | COMPROMETIDO
  String? manualResult; // '1a'|'1b'|'2a'|'2b'|'3'
  final notesCtrl = TextEditingController();

  String? computed() {
    if (realineacion == 'AUSENTE') return '3';
    if (realineacion == null || (realineacion != 'AUSENTE' && color == null)) {
      return null;
    }
    final base = realineacion == 'SIN_TENSION' ? '1' : '2';
    return '$base${color == 'NORMAL' ? 'a' : 'b'}';
  }

  String labelFor(String r) {
    switch (r) {
      case '1a':
        return '1a · Se realinea sin tensión, color normal';
      case '1b':
        return '1b · Se realinea sin tensión, color comprometido';
      case '2a':
        return '2a · No realinea del todo, color normal';
      case '2b':
        return '2b · No realinea del todo, color comprometido';
      case '3':
        return '3 · Colgajo ausente';
    }
    return r;
  }

  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final result = manual ? manualResult : computed();
        final comprometido =
            result != null && (result.endsWith('b') || result == '3');
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 4,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('STAR · Desgarro cutáneo',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Realizar')),
                    ButtonSegment(value: true, label: Text('Ya tengo el resultado')),
                  ],
                  selected: {manual},
                  onSelectionChanged: (s) => setSheet(() => manual = s.first),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!manual) ...[
                          const Text('Realineación del colgajo',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final o in const [
                                ('SIN_TENSION', 'Se realinea sin tensión'),
                                ('NO_COMPLETA', 'No se realinea del todo'),
                                ('AUSENTE', 'Colgajo ausente'),
                              ])
                                ChoiceChip(
                                  label: Text(o.$2,
                                      style: const TextStyle(fontSize: 12)),
                                  selected: realineacion == o.$1,
                                  onSelected: (_) =>
                                      setSheet(() => realineacion = o.$1),
                                ),
                            ],
                          ),
                          if (realineacion != null &&
                              realineacion != 'AUSENTE') ...[
                            const SizedBox(height: 12),
                            const Text('Color del colgajo',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                for (final o in const [
                                  ('NORMAL', 'Normal'),
                                  ('COMPROMETIDO', 'Pálido/oscuro/cianótico'),
                                ])
                                  ChoiceChip(
                                    label: Text(o.$2,
                                        style: const TextStyle(fontSize: 12)),
                                    selected: color == o.$1,
                                    onSelected: (_) =>
                                        setSheet(() => color = o.$1),
                                  ),
                              ],
                            ),
                          ],
                        ] else ...[
                          const Text('Resultado',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          for (final r in const ['1a', '1b', '2a', '2b', '3'])
                            RadioListTile<String>(
                              value: r,
                              groupValue: manualResult,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(labelFor(r),
                                  style: const TextStyle(fontSize: 13)),
                              onChanged: (v) =>
                                  setSheet(() => manualResult = v),
                            ),
                        ],
                        const SizedBox(height: 12),
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
                const SizedBox(height: 8),
                if (comprometido)
                  Text(
                      'Color comprometido → reevaluar en 24–48 h (se agenda en la '
                      'bitácora).',
                      style: TextStyle(
                          fontSize: 11, color: KuraColors.danger)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        result == null
                            ? 'Completa la valoración'
                            : 'Resultado: ${labelFor(result)}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: result == null
                                ? KuraColors.darkText.withValues(alpha: 0.6)
                                : KuraColors.primary),
                      ),
                    ),
                    FilledButton(
                      onPressed: result == null
                          ? null
                          : () => Navigator.of(ctx).pop(true),
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

  if (saved != true) return null;
  final category = manual ? manualResult : computed();
  if (category == null) return null;
  final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
  return (
    category: category,
    subscores: <String, dynamic>{
      'modo': manual ? 'manual' : 'guiada',
      if (!manual) 'realineacion': realineacion,
      if (!manual) 'color_colgajo': color,
    },
    notes: notes,
  );
}
