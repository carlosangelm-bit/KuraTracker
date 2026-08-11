import 'package:flutter/material.dart';

/// Triage de valoración: un solo cuestionario que captura las SEÑALES del
/// paciente que no se derivan del expediente. Con esas señales (+ comorbilidades,
/// heridas y Braden del expediente) el motor de aplicabilidad decide QUÉ escalas
/// se deben realizar. Devuelve el mapa de respuestas o null si se cancela.
Future<Map<String, bool>?> showTriageSheet(
  BuildContext context, {
  Map<String, bool>? initial,
}) async {
  // (id de señal, etiqueta) — el id coincide con los predicados 'triage' del
  // asset scale_applicability.json.
  const signals = <(String, String)>[
    ('incontinencia', 'Incontinencia o piel húmeda'),
    ('lesion_pie', 'Lesión en el pie'),
    ('desgarro', 'Desgarro cutáneo (skin tear)'),
    ('dispositivo', 'Presión por dispositivo médico (sonda, TET, mascarilla…)'),
    ('adhesivo', 'Daño por adhesivo médico (cinta, apósito, electrodo)'),
    ('herida_quirurgica', 'Herida quirúrgica'),
    ('iv_vesicante', 'Terapia IV con vesicante/irritante (riesgo de extravasación)'),
    ('quemadura', 'Quemadura'),
  ];
  final answers = <String, bool>{
    for (final s in signals) s.$1: initial?[s.$1] ?? false,
  };

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 4,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
        ),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Text('Triage de valoración',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Text(
                    'Marca lo que aplique. Con esto se determinan las escalas a '
                    'realizar (la diabetes, las heridas y el Braden ya se toman '
                    'del expediente).',
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in signals)
                      SwitchListTile(
                        dense: true,
                        title: Text(s.$2, style: const TextStyle(fontSize: 14)),
                        value: answers[s.$1]!,
                        onChanged: (v) => setSheet(() => answers[s.$1] = v),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Guardar triage'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  return ok == true ? answers : null;
}
