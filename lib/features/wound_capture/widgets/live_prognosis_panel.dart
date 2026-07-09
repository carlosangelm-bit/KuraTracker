import 'package:flutter/material.dart';
import '../../../core/theme/kura_theme.dart';
import '../../../engine/models/kura_engine_enums.dart';
import '../../../engine/models/kura_engine_output.dart';

/// Panel de pronostico en vivo (seccion 6.1 y 8.3): muestra el escenario
/// dominante, las 3 probabilidades como barras, el fenotipo comercial y
/// alertas, actualizandose en tiempo real mientras el clinico captura.
/// Siempre incluye la etiqueta de apoyo a la decision clinica (seccion 9).
class LivePrognosisPanel extends StatelessWidget {
  final KuraEngineOutput? output;
  final bool isLoading;
  final bool hasMinimumData;

  const LivePrognosisPanel({
    super.key,
    required this.output,
    required this.isLoading,
    required this.hasMinimumData,
  });

  Color _scenarioColor(KuraScenario s) {
    switch (s) {
      case KuraScenario.a:
        return KuraColors.scenarioA;
      case KuraScenario.b:
        return KuraColors.scenarioB;
      case KuraScenario.c:
        return KuraColors.scenarioC;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [KuraColors.primary.withOpacity(0.06), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KuraColors.primary.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: KuraColors.primary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Pronóstico en vivo — Protocolo Kura+',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Apoyo a la decisión clínica — no sustituye el juicio clínico.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: KuraColors.darkText.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 14),
          if (!hasMinimumData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Registra al menos el largo y ancho de la herida para ver el pronóstico.',
                style: TextStyle(color: KuraColors.darkText.withOpacity(0.5)),
              ),
            )
          else if (output == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Calculando...'),
            )
          else
            ...[
              for (final scenario in [KuraScenario.a, KuraScenario.b, KuraScenario.c])
                _ScenarioBar(
                  scenario: scenario,
                  probability: output!.probabilities[scenario] ?? 0,
                  isDominant: output!.dominantScenario == scenario,
                  color: _scenarioColor(scenario),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _scenarioColor(output!.dominantScenario).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag, color: _scenarioColor(output!.dominantScenario), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Escenario ${output!.dominantScenario.code} · ${output!.dominantScenario.title}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _scenarioColor(output!.dominantScenario),
                            ),
                          ),
                          Text(output!.dominantScenario.clinicalMeaning,
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(
                            'Fenotipo: ${output!.dominantScenario.treatmentPhenotype} '
                            '(${output!.dominantScenario.commercialPhenotype})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (output!.alertas.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...output!.alertas.map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: KuraColors.danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: KuraColors.danger.withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: KuraColors.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(a,
                                style: const TextStyle(
                                    fontSize: 12, color: KuraColors.danger,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    )),
              ],
              if (output!.interconsultas.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: output!.interconsultas
                      .map((i) => Chip(
                            avatar: Icon(
                              i.esUrgente ? Icons.priority_high : Icons.forward_to_inbox,
                              size: 16,
                              color: i.esUrgente ? KuraColors.danger : KuraColors.infoBlue,
                            ),
                            label: Text(i.especialidad, style: const TextStyle(fontSize: 11)),
                            backgroundColor: (i.esUrgente ? KuraColors.danger : KuraColors.infoBlue)
                                .withOpacity(0.08),
                          ))
                      .toList(),
                ),
              ],
            ],
        ],
      ),
    );
  }
}

class _ScenarioBar extends StatelessWidget {
  final KuraScenario scenario;
  final double probability;
  final bool isDominant;
  final Color color;

  const _ScenarioBar({
    required this.scenario,
    required this.probability,
    required this.isDominant,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              '${scenario.code} · ${scenario.title}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isDominant ? FontWeight.w800 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: probability,
                minHeight: 14,
                backgroundColor: KuraColors.chipBg,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              '${(probability * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: isDominant ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
