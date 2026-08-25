import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';

/// Sheet de la escala **GLOBIAD** (dermatitis asociada a incontinencia, DAI).
/// Dos modos, como Braden: REALIZARLA en la plataforma (elegir categoría visual
/// CAT1/CAT2 + ¿infección? → resultado 1A/1B/2A/2B) o CAPTURAR el resultado
/// manualmente si el usuario ya lo tiene. Devuelve `(category, subscores, notes)`
/// o `null` si se cancela.
Future<({String category, Map<String, dynamic> subscores, String? notes})?>
    showGlobiadSheet(BuildContext context) async {
  var manual = false; // false = realizar guiada; true = capturar resultado
  String? cat; // 'CAT1' | 'CAT2'
  bool? infeccion; // signos de infección
  String? manualResult; // '1A'|'1B'|'2A'|'2B'
  final notesCtrl = TextEditingController();

  String? computed() {
    if (cat == null || infeccion == null) return null;
    final base = cat == 'CAT1' ? '1' : '2';
    return '$base${infeccion! ? 'B' : 'A'}';
  }

  String labelFor(String r) {
    switch (r) {
      case '1A':
        return '1A · Enrojecimiento persistente, sin infección';
      case '1B':
        return '1B · Enrojecimiento persistente, con infección';
      case '2A':
        return '2A · Pérdida de piel, sin infección';
      case '2B':
        return '2B · Pérdida de piel, con infección';
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
                const Text('GLOBIAD · Dermatitis por humedad (DAI)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text('Clasificación por inspección visual de la piel perineal/perianal.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Realizar')),
                    ButtonSegment(value: true, label: Text('Ya tengo el resultado')),
                  ],
                  selected: {manual},
                  onSelectionChanged: (s) => setSheet(() => manual = s.first),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!manual) ...[
                          const Text('Categoría visual',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text(
                                    'CAT1 · Piel enrojecida, íntegra',
                                    style: TextStyle(fontSize: 12)),
                                selected: cat == 'CAT1',
                                onSelected: (_) => setSheet(() => cat = 'CAT1'),
                              ),
                              ChoiceChip(
                                label: const Text(
                                    'CAT2 · Pérdida de piel',
                                    style: TextStyle(fontSize: 12)),
                                selected: cat == 'CAT2',
                                onSelected: (_) => setSheet(() => cat = 'CAT2'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('¿Signos de infección presentes?',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text('Sí'),
                                selected: infeccion == true,
                                onSelected: (_) =>
                                    setSheet(() => infeccion = true),
                              ),
                              ChoiceChip(
                                label: const Text('No'),
                                selected: infeccion == false,
                                onSelected: (_) =>
                                    setSheet(() => infeccion = false),
                              ),
                            ],
                          ),
                        ] else ...[
                          const Text('Resultado',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          for (final r in const ['1A', '1B', '2A', '2B'])
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
                const SizedBox(height: 12),
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
  final subscores = <String, dynamic>{
    'modo': manual ? 'manual' : 'guiada',
    if (!manual) 'categoria_visual': cat,
    if (!manual) 'signos_infeccion': infeccion,
  };
  return (category: category, subscores: subscores, notes: notes);
}
