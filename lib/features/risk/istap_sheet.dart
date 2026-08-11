import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';

/// Sheet de la escala **ISTAP** (desgarros cutáneos, LeBlanc 2013): clasificación
/// en 3 tipos por pérdida del colgajo. Es un solo ítem (elegir el tipo), así que
/// "realizar" y "capturar" coinciden: se elige el resultado con su descripción.
/// Devuelve `(category '1'|'2'|'3', subscores, notes)` o null si se cancela.
Future<({String category, Map<String, dynamic> subscores, String? notes})?>
    showIstapSheet(BuildContext context) async {
  String? tipo; // '1' | '2' | '3'
  final notesCtrl = TextEditingController();

  const opciones = <(String, String)>[
    ('1', 'Tipo 1 · Sin pérdida de piel: el colgajo cubre todo el lecho'),
    ('2', 'Tipo 2 · Pérdida parcial del colgajo: no cubre todo el lecho'),
    ('3', 'Tipo 3 · Pérdida total del colgajo: lecho completamente expuesto'),
  ];

  final saved = await showModalBottomSheet<bool>(
    context: context,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ISTAP · Desgarro cutáneo (skin tear)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            for (final o in opciones)
              RadioListTile<String>(
                value: o.$1,
                groupValue: tipo,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(o.$2, style: const TextStyle(fontSize: 13)),
                onChanged: (v) => setSheet(() => tipo = v),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tipo == null ? 'Elige el tipo' : 'ISTAP tipo $tipo',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: tipo == null
                            ? KuraColors.darkText.withValues(alpha: 0.6)
                            : KuraColors.primary),
                  ),
                ),
                FilledButton(
                  onPressed:
                      tipo == null ? null : () => Navigator.of(ctx).pop(true),
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (saved != true || tipo == null) return null;
  final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
  return (
    category: tipo!,
    subscores: <String, dynamic>{'tipo_istap': tipo},
    notes: notes,
  );
}
