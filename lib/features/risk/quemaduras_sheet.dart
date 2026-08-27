import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/params/clinical_params.dart';

/// Resultado de la escala de Quemaduras (profundidad + índice de Garcés).
typedef QuemaduraResult = ({
  String band, // Leve|Moderado|Grave|Crítico|Mortal
  double indice, // índice de Garcés
  bool criterioHospitalizacion,
  Map<String, dynamic> subscores,
  String? notes,
});

/// Índice de Garcés = %A×1 + %AB×2 + %B×3 + edad. **Fuente única** de la fórmula
/// (la usan el builder y el bloque post-pop). Devuelve null si no hay superficie
/// capturada: la fórmula suma la edad, así que sin superficie daría un índice
/// "fantasma" (= edad) y una banda que parecería calculada. La edad sola NO
/// cuenta como captura.
double? garcesIndex(
    {required double pa,
    required double pab,
    required double pb,
    required int edad}) {
  if (pa + pab + pb <= 0) return null;
  return pa * 1 + pab * 2 + pb * 3 + edad;
}

// Cortes (índice de Garcés y criterio ABA) parametrizados en ClinicalParams
// (assets/engine/clinical/thresholds.json) para que María los revise/ajuste sin
// recompilar. Si ClinicalParams no está cargado (p. ej. algún test), se cae a los
// valores por defecto del borrador.
String _bandForIndex(double idx) {
  final p = ClinicalParams.isLoaded ? ClinicalParams.instance : null;
  if (idx > (p?.garcesMortalAbove ?? 150)) return 'Mortal';
  if (idx >= (p?.garcesCriticoMin ?? 101)) return 'Crítico';
  if (idx >= (p?.garcesGraveMin ?? 71)) return 'Grave';
  if (idx >= (p?.garcesModeradoMin ?? 41)) return 'Moderado';
  return 'Leve';
}

/// Criterio de hospitalización ABA (borrador). Cortes en ClinicalParams.
bool _abaCriterio({
  required String? profundidad,
  required double scq,
  required int edad,
}) {
  final p = ClinicalParams.isLoaded ? ClinicalParams.instance : null;
  final scq2 = p?.aba2doGradoScqAbovePct ?? 10;
  final scq3 = p?.aba3erGradoScqAbovePct ?? 5;
  final edadPed = p?.abaEdadPediatricaBelow ?? 10;
  final edadAdm = p?.abaEdadAdultoMayorAbove ?? 50;
  final segundo =
      profundidad == 'SEGUNDO_SUP' || profundidad == 'SEGUNDO_PROF';
  return (segundo && scq > scq2 && (edad < edadPed || edad > edadAdm)) ||
      (profundidad == 'TERCER_GRADO' && scq > scq3);
}

/// Sheet de Quemaduras: profundidad (clasificación) + superficie por tipo (A/AB/B)
/// para el ÍNDICE DE GARCÉS = %A×1 + %AB×2 + %B×3 + edad. Modo REALIZAR (calcula)
/// o CAPTURAR el índice manualmente. La [edad] alimenta la fórmula.
Future<QuemaduraResult?> showQuemadurasSheet(
  BuildContext context, {
  required int edad,
}) async {
  var manual = false;
  String? profundidad; // PRIMER_GRADO | SEGUNDO_SUP | SEGUNDO_PROF | TERCER_GRADO
  final aCtrl = TextEditingController();
  final abCtrl = TextEditingController();
  final bCtrl = TextEditingController();
  final manualCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  double num0(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  const profundidades = <(String, String)>[
    ('PRIMER_GRADO', 'Primer grado (epidermis)'),
    ('SEGUNDO_SUP', 'Segundo grado superficial'),
    ('SEGUNDO_PROF', 'Segundo grado profundo'),
    ('TERCER_GRADO', 'Tercer grado (espesor total)'),
  ];

  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final pa = num0(aCtrl), pab = num0(abCtrl), pb = num0(bCtrl);
        final scq = pa + pab + pb;
        final indiceGuiado = garcesIndex(pa: pa, pab: pab, pb: pb, edad: edad);
        final indice = manual
            ? (double.tryParse(manualCtrl.text.trim().replaceAll(',', '.')))
            : indiceGuiado;
        // Criterio ABA (borrador): cortes en ClinicalParams (revisables por María).
        final abaCrit =
            _abaCriterio(profundidad: profundidad, scq: scq, edad: edad);
        final valid = indice != null && (manual || profundidad != null);
        final band = indice == null ? null : _bandForIndex(indice);
        final critico = band == 'Crítico' || band == 'Mortal';
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
                const Text('Quemaduras · Profundidad + índice de Garcés',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('Edad del paciente: $edad años (usada en la fórmula).',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Realizar')),
                    ButtonSegment(value: true, label: Text('Ya tengo el índice')),
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
                          const Text('Profundidad',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final p in profundidades)
                                ChoiceChip(
                                  label: Text(p.$2,
                                      style: const TextStyle(fontSize: 12)),
                                  selected: profundidad == p.$1,
                                  onSelected: (_) =>
                                      setSheet(() => profundidad = p.$1),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('% de superficie corporal quemada por tipo',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                  child: _pctField(aCtrl, 'A ×1',
                                      () => setSheet(() {}))),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _pctField(abCtrl, 'AB ×2',
                                      () => setSheet(() {}))),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _pctField(bCtrl, 'B ×3',
                                      () => setSheet(() {}))),
                            ],
                          ),
                        ] else
                          TextField(
                            controller: manualCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setSheet(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Índice de Garcés',
                                isDense: true,
                                border: OutlineInputBorder()),
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
                const SizedBox(height: 8),
                if (abaCrit && !manual)
                  Text('Cumple criterio de hospitalización (ABA).',
                      style: TextStyle(fontSize: 11, color: KuraColors.danger)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        band == null
                            ? 'Completa la valoración'
                            : 'Índice: ${indice!.toStringAsFixed(0)} · $band',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: critico
                                ? KuraColors.danger
                                : (valid
                                    ? KuraColors.primary
                                    : KuraColors.darkText
                                        .withValues(alpha: 0.6))),
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
  final pa = num0(aCtrl), pab = num0(abCtrl), pb = num0(bCtrl);
  final indice = manual
      ? double.tryParse(manualCtrl.text.trim().replaceAll(',', '.'))
      : garcesIndex(pa: pa, pab: pab, pb: pb, edad: edad);
  if (indice == null) return null;
  final scq = pa + pab + pb;
  final abaCrit = !manual &&
      _abaCriterio(profundidad: profundidad, scq: scq, edad: edad);
  final notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
  return (
    band: _bandForIndex(indice),
    indice: indice,
    criterioHospitalizacion: abaCrit,
    subscores: <String, dynamic>{
      'modo': manual ? 'manual' : 'guiada',
      if (!manual) 'profundidad': profundidad,
      if (!manual) 'pct_A': pa,
      if (!manual) 'pct_AB': pab,
      if (!manual) 'pct_B': pb,
      'edad': edad,
      'criterio_hospitalizacion': abaCrit,
    },
    notes: notes,
  );
}

Widget _pctField(TextEditingController c, String label, VoidCallback onChanged) =>
    TextField(
      controller: c,
      keyboardType: TextInputType.number,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
