import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';

/// Hoja genérica de una escala CATEGÓRICA de selección única (NPIAP, Wagner,
/// CEAP, MDRPI…): se elige una categoría con su descripción (realizar = capturar,
/// pues no hay cálculo). Devuelve `(category, subscores, notes)` o null.
Future<({String category, Map<String, dynamic> subscores, String? notes})?>
    showCategorySheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<(String, String)> options,
  String? footnote,
}) async {
  String? sel;
  final notesCtrl = TextEditingController();

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
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(ctx).textTheme.bodySmall),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final o in options)
                        RadioListTile<String>(
                          value: o.$1,
                          groupValue: sel,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title:
                              Text(o.$2, style: const TextStyle(fontSize: 13)),
                          onChanged: (v) => setSheet(() => sel = v),
                        ),
                      if (footnote != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: Text(footnote,
                              style: TextStyle(
                                  fontSize: 11, color: KuraColors.primary)),
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(sel == null ? 'Elige una opción' : 'Selección: $sel',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: sel == null
                                ? KuraColors.darkText.withValues(alpha: 0.6)
                                : KuraColors.primary)),
                  ),
                  FilledButton(
                    onPressed:
                        sel == null ? null : () => Navigator.of(ctx).pop(true),
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

  if (saved != true || sel == null) return null;
  final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
  return (
    category: sel!,
    subscores: <String, dynamic>{'valor': sel},
    notes: notes,
  );
}
