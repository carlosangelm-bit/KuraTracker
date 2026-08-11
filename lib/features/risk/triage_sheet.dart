import 'package:flutter/material.dart';

import '../../engine/risk/scale_applicability.dart';

/// Cuestionario inicial de FACTORES DE RIESGO: un solo formulario que enfermería
/// puede llenar SIN diagnosticar. Marca los factores observables del paciente;
/// con esos factores (+ diabetes, heridas, Braden, edad y estancia del
/// expediente) el motor de aplicabilidad decide QUÉ escalas se deben realizar.
/// Los grupos y las etiquetas vienen del catálogo (asset), así que se ajustan sin
/// tocar código. Devuelve el mapa factor→bool, o null si se cancela.
Future<Map<String, bool>?> showTriageSheet(
  BuildContext context, {
  required List<QuestionnaireGroup> groups,
  required String Function(String) factorLabel,
  Map<String, bool>? initial,
}) async {
  final allFactors = [for (final g in groups) ...g.factors];
  final answers = <String, bool>{
    for (final id in allFactors) id: initial?[id] ?? false,
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
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Text('Cuestionario de factores de riesgo',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Text(
                    'Marca los factores que observes en el paciente. Con esto se '
                    'determinan las escalas a realizar; la diabetes, las heridas, '
                    'la edad, el Braden y la estancia ya se toman del expediente.',
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 12, 2),
                        child: Text(g.group.toUpperCase(),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: Theme.of(ctx).colorScheme.primary)),
                      ),
                      for (final id in g.factors)
                        SwitchListTile(
                          dense: true,
                          title: Text(factorLabel(id),
                              style: const TextStyle(fontSize: 14)),
                          value: answers[id]!,
                          onChanged: (v) => setSheet(() => answers[id] = v),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Guardar cuestionario'),
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
