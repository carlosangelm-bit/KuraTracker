import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';

/// Sheet de la escala **MARSI** (lesión cutánea por adhesivos médicos):
/// clasificación por MECANISMO (no numérica). Un solo ítem. Devuelve
/// `(category, subscores, notes)` o null si se cancela.
Future<({String category, Map<String, dynamic> subscores, String? notes})?>
    showMarsiSheet(BuildContext context) async {
  String? mecanismo; // MECANICA | DERMATITIS | OTRAS
  final notesCtrl = TextEditingController();

  const opciones = <(String, String)>[
    ('MECANICA',
        'Mecánica: desprendimiento epidérmico, ampollas o desgarros al retirar'),
    ('DERMATITIS',
        'Dermatitis: reacción irritativa o alérgica al adhesivo'),
    ('OTRAS', 'Otras: maceración por humedad atrapada, foliculitis'),
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
            const Text('MARSI · Lesión por adhesivo médico',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            for (final o in opciones)
              RadioListTile<String>(
                value: o.$1,
                groupValue: mecanismo,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(o.$2, style: const TextStyle(fontSize: 13)),
                onChanged: (v) => setSheet(() => mecanismo = v),
              ),
            if (mecanismo == 'MECANICA')
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                    'Si el daño es un desgarro cutáneo, clasifícalo también con '
                    'ISTAP.',
                    style: TextStyle(fontSize: 11, color: KuraColors.primary)),
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
                const Expanded(child: SizedBox()),
                FilledButton(
                  onPressed: mecanismo == null
                      ? null
                      : () => Navigator.of(ctx).pop(true),
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (saved != true || mecanismo == null) return null;
  final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
  return (
    category: mecanismo!,
    subscores: <String, dynamic>{'mecanismo_marsi': mecanismo},
    notes: notes,
  );
}
