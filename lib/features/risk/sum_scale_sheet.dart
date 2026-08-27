import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/risk/sum_scale.dart';

/// Color por severidad de banda: danger→rojo, warn→ámbar de advertencia,
/// watch/ok/null→neutro (color de marca). Compartido por la hoja de captura y la
/// tarjeta de escalas para que el mismo resultado se lea igual en ambos lados.
Color scaleSeverityColor(String? severity) {
  switch (severity) {
    case 'danger':
      return KuraColors.danger;
    case 'warn':
      return KuraColors.warning;
    default:
      return KuraColors.primary;
  }
}

/// Hoja genérica de una escala tipo SUMA (PUSH, RESVECH, ASEPSIS…) definida en un
/// asset. Dos modos: REALIZAR (ítems radio + medición de área → total calculado)
/// o CAPTURAR el total manualmente. Devuelve `(total, subscores, notes)` o null.
Future<({double total, Map<String, dynamic> subscores, String? notes})?>
    showSumScaleSheet(BuildContext context, SumScaleDef def,
        {num? previousTotal}) async {
  var manual = false;
  final selections = <String, int>{}; // itemId (radio) → score
  final areaCtrls = <String, (TextEditingController, TextEditingController)>{
    for (final it in def.items)
      if (it.type == 'area')
        it.id: (TextEditingController(), TextEditingController()),
  };
  final manualCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  double? areaValue(SumItem it) {
    final c = areaCtrls[it.id]!;
    final l = double.tryParse(c.$1.text.replaceAll(',', '.'));
    final w = double.tryParse(c.$2.text.replaceAll(',', '.'));
    if (l == null || w == null) return null;
    return l * w;
  }

  int? guidedTotal() {
    var sum = 0;
    for (final it in def.items) {
      if (it.type == 'area') {
        final a = areaValue(it);
        if (a == null) return null;
        sum += it.pointsForArea(a);
      } else {
        final s = selections[it.id];
        if (s == null) return null;
        sum += s;
      }
    }
    return sum;
  }

  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final gTotal = guidedTotal();
        final mTotal = int.tryParse(manualCtrl.text.trim());
        final total = manual ? mTotal : gTotal;
        final valid =
            total != null && total >= def.totalMin && total <= def.totalMax;
        // Vista previa de la interpretación: bandas y —si hay valoración
        // previa— también la tendencia, para que el clínico la vea ANTES de
        // guardar (no solo después).
        final reading =
            total == null ? null : def.interpret(total, previousTotal: previousTotal);
        final trendSuffix = (reading?.delta != null && reading!.delta != 0)
            ? ' (${reading.delta! < 0 ? '↓' : '↑'}${reading.delta!.abs().toStringAsFixed(0)})'
            : '';
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
                Text(def.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                if (def.draft)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        'Borrador: sub-puntajes pendientes de validación clínica.',
                        style: TextStyle(fontSize: 11, color: KuraColors.danger)),
                  ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Realizar')),
                    ButtonSegment(
                        value: true, label: Text('Ya tengo el total')),
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
                        if (!manual)
                          for (final it in def.items) ...[
                            Text(it.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 6),
                            if (it.type == 'area')
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: areaCtrls[it.id]!.$1,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setSheet(() {}),
                                      decoration: const InputDecoration(
                                          labelText: 'Largo (cm)',
                                          isDense: true,
                                          border: OutlineInputBorder()),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: areaCtrls[it.id]!.$2,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setSheet(() {}),
                                      decoration: const InputDecoration(
                                          labelText: 'Ancho (cm)',
                                          isDense: true,
                                          border: OutlineInputBorder()),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final o in it.options)
                                    ChoiceChip(
                                      label: Text('${o.score} · ${o.label}',
                                          style: const TextStyle(fontSize: 12)),
                                      selected: selections[it.id] == o.score,
                                      onSelected: (_) => setSheet(
                                          () => selections[it.id] = o.score),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 12),
                          ]
                        else
                          TextField(
                            controller: manualCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setSheet(() {}),
                            decoration: InputDecoration(
                              labelText:
                                  'Total (${def.totalMin}–${def.totalMax})',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
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
                      child: Text(
                        total == null
                            ? 'Completa la valoración'
                            : 'Total: $total / ${def.totalMax}'
                                '${reading?.label != null ? ' · ${reading!.label}$trendSuffix' : ''}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: (total == null || !valid)
                                ? KuraColors.darkText.withValues(alpha: 0.6)
                                : scaleSeverityColor(reading?.severity)),
                      ),
                    ),
                    FilledButton(
                      onPressed:
                          valid ? () => Navigator.of(ctx).pop(true) : null,
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
  final total = manual ? int.tryParse(manualCtrl.text.trim()) : guidedTotal();
  if (total == null) return null;
  final subscores = <String, dynamic>{'modo': manual ? 'manual' : 'guiada'};
  if (!manual) {
    for (final it in def.items) {
      if (it.type == 'area') {
        final a = areaValue(it);
        subscores['area_cm2'] = a;
        if (a != null) subscores[it.id] = it.pointsForArea(a);
      } else {
        subscores[it.id] = selections[it.id];
      }
    }
  }
  final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
  return (total: total.toDouble(), subscores: subscores, notes: notes);
}
