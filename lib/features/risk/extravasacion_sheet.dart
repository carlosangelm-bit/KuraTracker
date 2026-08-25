import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';

/// Sheet de **Extravasación** (lesión por fármaco vesicante/irritante):
/// clasificación por grados 0–4 (color + integridad). Devuelve
/// `(category '0'..'4', subscores, notes)` o null si se cancela.
Future<({String category, Map<String, dynamic> subscores, String? notes})?>
    showExtravasacionSheet(BuildContext context) async {
  String? grado; // '0'..'4'
  final notesCtrl = TextEditingController();

  const opciones = <(String, String)>[
    ('0', 'Grado 0 · Piel normal, sin lesión'),
    ('1', 'Grado 1 · Rosado, piel intacta'),
    ('2', 'Grado 2 · Rojo, ampolla'),
    ('3', 'Grado 3 · Blanqueado, pérdida superficial de piel'),
    ('4', 'Grado 4 · Ennegrecido, pérdida tisular / necrosis'),
  ];

  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
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
              const Text('Extravasación · Grado',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 2),
              Text(
                  'Detén la infusión, aspira la vía y registra. Grados 1–4: '
                  'monitorización c/4 h e interconsulta a cirugía plástica.',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final o in opciones)
                        RadioListTile<String>(
                          value: o.$1,
                          groupValue: grado,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title:
                              Text(o.$2, style: const TextStyle(fontSize: 13)),
                          onChanged: (v) => setSheet(() => grado = v),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Agente / notas (opcional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      grado == null ? 'Elige el grado' : 'Grado $grado',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: (grado != null && grado != '0')
                              ? KuraColors.danger
                              : (grado == null
                                  ? KuraColors.darkText.withValues(alpha: 0.6)
                                  : KuraColors.primary)),
                    ),
                  ),
                  FilledButton(
                    onPressed:
                        grado == null ? null : () => Navigator.of(ctx).pop(true),
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (saved != true || grado == null) return null;
  final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
  return (
    category: grado!,
    subscores: <String, dynamic>{'grado_extravasacion': grado},
    notes: notes,
  );
}
