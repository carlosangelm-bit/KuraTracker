import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/kura_sheehan_checkpoint.dart';
import '../../services/data_repository.dart';

/// Vista de seguimiento comparativa (seccion 6.1): grafica de tendencia de
/// area en el tiempo + checkpoint de Sheehan integrado. La comparativa de
/// fotos lado a lado (basal vs actual) se representa con placeholders ya
/// que el almacenamiento real de imagenes requiere Supabase Storage
/// configurado (ver README, seccion "Proximos pasos").
class FollowUpScreen extends ConsumerWidget {
  final String patientId;
  final String woundId;
  const FollowUpScreen({super.key, required this.patientId, required this.woundId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final dateFmt = DateFormat('dd/MM');

    return Scaffold(
      appBar: AppBar(title: const Text('Seguimiento de herida')),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final wound = repo.getWound(woundId);
          final measurements = repo.listMeasurementsForWound(woundId);
          if (wound == null || measurements.isEmpty) {
            return const Center(child: Text('Sin mediciones registradas para esta herida.'));
          }
          final baseline = measurements.first;
          final current = measurements.last;
          final weeksSinceBaseline =
              current.measuredAt.difference(baseline.measuredAt).inDays ~/ 7;

          final checkpoint = KuraSheehanCheckpoint.evaluate(
            semana: weeksSinceBaseline.clamp(1, 52),
            areaBasalCm2: baseline.areaCm2,
            areaActualCm2: current.areaCm2,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(wound.etiology.label,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${measurements.length} mediciones registradas'),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tendencia de área (cm²)',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 220,
                          child: LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: true),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final idx = value.toInt();
                                      if (idx < 0 || idx >= measurements.length) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          dateFmt.format(measurements[idx].measuredAt),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                                ),
                                rightTitles:
                                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles:
                                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: [
                                    for (var i = 0; i < measurements.length; i++)
                                      FlSpot(i.toDouble(), measurements[i].areaCm2),
                                  ],
                                  isCurved: true,
                                  color: KuraColors.primary,
                                  barWidth: 3,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: KuraColors.primary.withOpacity(0.1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timeline, color: KuraColors.primary),
                            const SizedBox(width: 8),
                            Text('Checkpoint de Sheehan · Semana ${checkpoint.semana}',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildGauge(checkpoint),
                        const SizedBox(height: 12),
                        Text(
                          'Reducción: ${checkpoint.pctReduccionBruta.toStringAsFixed(1)}% '
                          '(umbral cierre ${checkpoint.umbralCierre.toStringAsFixed(0)}% · '
                          'umbral alerta ${checkpoint.umbralAlerta.toStringAsFixed(0)}%)',
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _decisionColor(checkpoint.decision).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.flag, color: _decisionColor(checkpoint.decision)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  checkpoint.decision.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _decisionColor(checkpoint.decision),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _PhotoPlaceholder(label: 'Basal', date: baseline.measuredAt)),
                    const SizedBox(width: 12),
                    Expanded(child: _PhotoPlaceholder(label: 'Actual', date: current.measuredAt)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _decisionColor(SheehanDecision d) {
    switch (d) {
      case SheehanDecision.confirmarCierre:
        return KuraColors.success;
      case SheehanDecision.extenderObservacion:
        return KuraColors.warning;
      case SheehanDecision.reclasificarC:
        return KuraColors.danger;
    }
  }

  Widget _buildGauge(SheehanCheckpointResult checkpoint) {
    final pct = checkpoint.pctReduccionBruta.clamp(0, 100) / 100;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: pct.toDouble(),
        minHeight: 16,
        backgroundColor: KuraColors.chipBg,
        color: _decisionColor(checkpoint.decision),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  final String label;
  final DateTime date;
  const _PhotoPlaceholder({required this.label, required this.date});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: KuraColors.chipBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KuraColors.borderSubtle),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_outlined, size: 32, color: KuraColors.darkText),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
