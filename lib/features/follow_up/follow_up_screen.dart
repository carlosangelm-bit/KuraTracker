import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/kura_sheehan_checkpoint.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/sheehan_decision_style.dart';
import '../../engine/wound_deterioration_evaluator.dart';
import '../../models/treatment_plan.dart';
import '../../models/wound.dart';
import '../../services/photo_upload_service.dart';

/// Calcula, para una medicion dada, las 4 sumas acumuladas normalizadas
/// (0-100) de composicion del lecho en el orden granulacion / +esfacelo /
/// +necrosis / +epitelizacion, usadas para el grafico de lineas apiladas
/// al 100% en [FollowUpScreen]. Se normaliza dividiendo por
/// [WoundMeasurement.bedCompositionSum] porque la captura del dato no
/// garantiza que los 4 porcentajes sumen exactamente 100 (ver
/// `canSave` en follow_up_capture_screen.dart, que no valida la suma).
/// Si la suma original es 0 (dato incompleto/no capturado), se devuelve
/// [0, 0, 0, 0] en vez de forzar un 100% que no fue realmente medido.
List<double> bedCompositionCumulative(WoundMeasurement m) {
  final sum = m.bedCompositionSum;
  if (sum <= 0.0001) return [0.0, 0.0, 0.0, 0.0];
  final g = m.granulationPct / sum * 100;
  final s = m.sloughPct / sum * 100;
  final n = m.necrosisPct / sum * 100;
  final e = m.epithelializationPct / sum * 100;
  final c0 = g;
  final c1 = c0 + s;
  final c2 = c1 + n;
  final c3 = (c2 + e).clamp(0.0, 100.0);
  return [c0, c1, c2, c3];
}

/// Vista de seguimiento comparativa (seccion 6.1): grafica de tendencia de
/// area en el tiempo + checkpoint de Sheehan integrado, derivados 100% de
/// la serie real de wound_measurements/wound_photos (sin datos de ejemplo
/// ni fallback hardcodeado). Las tablas de umbrales del checkpoint de
/// Sheehan (KuraSheehanCheckpoint._umbralesOficiales) SI son constantes
/// legitimas del protocolo clinico y no se tocan.
class FollowUpScreen extends ConsumerWidget {
  final String patientId;
  final String woundId;
  const FollowUpScreen({super.key, required this.patientId, required this.woundId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final dateFmt = DateFormat('dd/MM');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguimiento de herida'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add_circle_outline, color: KuraColors.primary),
            label: const Text('Registrar seguimiento',
                style: TextStyle(color: KuraColors.primary)),
            onPressed: () =>
                context.go('/patients/$patientId/wound/$woundId/follow-up/new'),
          ),
        ],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final wound = repo.getWound(woundId);
          final measurements = repo.listMeasurementsForWound(woundId);
          if (wound == null || measurements.isEmpty) {
            return const Center(child: Text('Sin mediciones registradas para esta herida.'));
          }
          // listMeasurementsForWound ya devuelve la lista ordenada
          // ascendente por measured_at (ver DataRepository): basal = primera
          // medicion (valoracion inicial), actual = mas reciente. Con esto
          // el tablero se deriva 100% de la serie real; si solo existe la
          // basal (0 seguimientos), se muestra un estado vacio en vez de
          // calcular un checkpoint contra si misma.
          final baseline = measurements.first;
          final current = measurements.last;
          final hasFollowUps = measurements.length > 1;
          // Consulta inmediatamente anterior a la actual (NO la basal),
          // usada exclusivamente para el deterioro de trayectoria
          // (kura_rules_v2). Si solo hay 2 mediciones, "previous" coincide
          // con "baseline".
          final previous = hasFollowUps ? measurements[measurements.length - 2] : null;

          final weeksSinceBaseline =
              current.measuredAt.difference(baseline.measuredAt).inDays ~/ 7;

          // Evaluacion clinica de una medicion dada (misma consulta). Se
          // empata por consultationId cuando es posible; si no hay match
          // directo (dato legado sin consultation_id), se cae a la
          // evaluacion cuya consulta tenga la fecha mas reciente. Mismo
          // criterio que WoundCheckpointDeriver.
          WoundAssessment? matchAssessment(
              List<WoundAssessment> assessments, WoundMeasurement measurement) {
            final matching = assessments
                .where((a) => a.consultationId == measurement.consultationId)
                .toList();
            if (matching.isNotEmpty) return matching.first;
            if (assessments.isEmpty) return null;
            final withDates = assessments
                .map((a) => (
                      assessment: a,
                      date: repo.getConsultation(a.consultationId)?.visitDate ??
                          DateTime.fromMillisecondsSinceEpoch(0),
                    ))
                .toList()
              ..sort((x, y) => x.date.compareTo(y.date));
            return withDates.last.assessment;
          }

          WoundAssessment? latestAssessment;
          WoundAssessment? previousAssessment;
          if (hasFollowUps) {
            final assessments = repo.listAssessmentsForWound(woundId);
            latestAssessment = matchAssessment(assessments, current);
            if (previous != null) {
              previousAssessment = matchAssessment(assessments, previous);
            }
          }

          // Deterioro objetivo de trayectoria (kura_rules_v2): compara la
          // consulta actual contra la INMEDIATAMENTE ANTERIOR (no la
          // basal). Ver WoundDeteriorationEvaluator para el detalle de
          // cada criterio.
          final deterioro = previous != null
              ? WoundDeteriorationEvaluator.evaluate(
                  current: current,
                  previous: previous,
                  currentAssessment: latestAssessment,
                  previousAssessment: previousAssessment,
                )
              : WoundDeteriorationResult.none;

          final checkpoint = hasFollowUps
              ? KuraSheehanCheckpoint.evaluate(
                  semana: weeksSinceBaseline.clamp(1, 52),
                  areaBasalCm2: baseline.areaCm2,
                  areaActualCm2: current.areaCm2,
                  // Definitivo: campo capturado explicitamente en el
                  // formulario de seguimiento (wound_assessments.low_adherence).
                  bajaAdherencia: latestAssessment?.lowAdherence ?? false,
                  // INTERINO — pendiente de validar con la Dra. Capistran
                  // la representacion/umbral oficial de IWII (14 criterios
                  // vs. 3 niveles de severidad). Proxy actual: cualquier
                  // criterio de infeccion marcado en la evaluacion.
                  infeccionActiva: latestAssessment?.infectionCriteria.isNotEmpty ?? false,
                  // Definitivo (kura_rules_v2): deterioro objetivo del
                  // lecho y aumento de exudado, ambos comparados contra la
                  // consulta inmediatamente anterior.
                  deterioroDelLecho: deterioro.deterioroDelLecho,
                  aumentoDeExudado: deterioro.aumentoDeExudado,
                )
              : null;

          final photos = repo.listPhotosForWound(woundId).toList()
            ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
          final baselinePhoto = photos.isNotEmpty ? photos.first : null;
          final currentPhoto = photos.isNotEmpty ? photos.last : null;

          // Regla de decision clinica (Protocolo de Desbridamiento SS13): si
          // no hay avance (reduccion de area) en una ventana de 2-4 semanas,
          // sugerir referir a especialista o replantear el plan. Se busca,
          // entre las mediciones reales ya registradas, la mas cercana a esa
          // ventana antes de la medicion actual; si aun no existe ninguna
          // medicion con esa antiguedad, la regla simplemente no aplica
          // todavia (sin inventar datos).
          final referenceForProgress =
              hasFollowUps ? _referenceMeasurementForWindow(measurements, current) : null;
          final noProgressInWindow =
              referenceForProgress != null && current.areaCm2 >= referenceForProgress.areaCm2;

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
                Text('${measurements.length} mediciones registradas'
                    '${hasFollowUps ? '' : ' (solo valoración basal)'}'),
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
                                  // Un punto por visita: basal = indice 0,
                                  // luego una entrada por cada seguimiento
                                  // registrado, en el orden real de
                                  // measured_at (nunca basal-vs-actual
                                  // solamente).
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
                // Volumen (feat/volume-kundin-charts): additive, no toca la
                // grafica de area existente. Heridas superficiales sin
                // profundidad tienen volumeCm3 == null (no aplica) y se
                // omiten de la serie sin romper el eje X (que sigue
                // alineado por indice/fecha con measurements, igual que la
                // grafica de area) para poder comparar visitas.
                _buildVolumeCard(measurements, dateFmt),
                const SizedBox(height: 20),
                // Composicion de tejido en el tiempo (granulacion / esfacelo
                // / necrosis / epitelizacion), misma serie que la grafica de
                // area (additive).
                _buildTissueCompositionCard(measurements, dateFmt),
                const SizedBox(height: 20),
                if (checkpoint == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(Icons.hourglass_empty,
                              size: 32, color: KuraColors.darkText.withOpacity(0.4)),
                          const SizedBox(height: 10),
                          const Text('Aún sin seguimientos',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            'Registra una visita de seguimiento para calcular el '
                            'checkpoint de Sheehan y la tendencia de reducción.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                          ),
                        ],
                      ),
                    ),
                  )
                else
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
                              Expanded(
                                child: Text('Checkpoint de Sheehan · Semana ${checkpoint.semana}',
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildGauge(checkpoint),
                          const SizedBox(height: 12),
                          Text(
                            'Reducción bruta: ${checkpoint.pctReduccionBruta.toStringAsFixed(1)}% '
                            '(umbral cierre ${checkpoint.umbralCierre.toStringAsFixed(0)}% · '
                            'umbral alerta ${checkpoint.umbralAlerta.toStringAsFixed(0)}%)',
                          ),
                          if (checkpoint.penalizacionesAplicadas.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Reducción ajustada: '
                              '${checkpoint.pctReduccionAjustada.toStringAsFixed(1)}%',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: checkpoint.penalizacionesAplicadas
                                  .map((p) => Chip(
                                        avatar: const Icon(Icons.remove_circle_outline,
                                            size: 16, color: KuraColors.danger),
                                        label: Text('$p −5 pp', style: const TextStyle(fontSize: 11)),
                                        backgroundColor: KuraColors.danger.withOpacity(0.08),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ))
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: checkpoint.decision.toProgressStatus.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.flag, color: checkpoint.decision.toProgressStatus.color),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    checkpoint.decision.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: checkpoint.decision.toProgressStatus.color,
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
                if (noProgressInWindow) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: KuraColors.danger.withOpacity(0.06),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: KuraColors.danger),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sin avance en 2–4 semanas: considerar referir a especialista',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800, color: KuraColors.danger),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'El área no se redujo entre '
                                  '${dateFmt.format(referenceForProgress.measuredAt)} '
                                  '(${referenceForProgress.areaCm2.toStringAsFixed(1)} cm²) y '
                                  '${dateFmt.format(current.measuredAt)} '
                                  '(${current.areaCm2.toStringAsFixed(1)} cm²). '
                                  'Protocolo de Desbridamiento §13: replantear el plan de '
                                  'tratamiento o generar una interconsulta.',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _WoundPhotoCard(
                        label: 'Basal',
                        date: baseline.measuredAt,
                        photo: baselinePhoto,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _WoundPhotoCard(
                        label: 'Actual',
                        date: current.measuredAt,
                        photo: currentPhoto,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGauge(SheehanCheckpointResult checkpoint) {
    // El gauge refleja el % ajustado (con penalizaciones), que es el valor
    // real usado para tomar la decision — no el bruto.
    final pct = checkpoint.pctReduccionAjustada.clamp(0, 100) / 100;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: pct.toDouble(),
        minHeight: 16,
        backgroundColor: KuraColors.chipBg,
        color: checkpoint.decision.toProgressStatus.color,
      ),
    );
  }

  /// Grafica de volumen en el tiempo (feat/volume-kundin-charts). Solo
  /// incluye en la serie las visitas con volumeCm3 != null (heridas
  /// profundas medidas en 3D); las superficiales se omiten sin romper el
  /// eje X, que sigue alineado por indice/fecha con la lista completa de
  /// `measurements` (mismo criterio que la grafica de area) para poder
  /// leer "en que visita" cae cada punto. Si NINGUNA visita tiene volumen
  /// (herida siempre superficial), se muestra un placeholder explicito en
  /// vez de una grafica vacia.
  Widget _buildVolumeCard(List<WoundMeasurement> measurements, DateFormat dateFmt) {
    final volumePoints = <MapEntry<int, WoundMeasurement>>[
      for (var i = 0; i < measurements.length; i++)
        if (measurements[i].volumeCm3 != null) MapEntry(i, measurements[i]),
    ];

    if (volumePoints.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tendencia de volumen (cm³)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.inbox_outlined, size: 20, color: KuraColors.darkText.withOpacity(0.4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sin mediciones de volumen (herida superficial: no se activa '
                      'la medición 3D).',
                      style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tendencia de volumen (cm³)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Fórmula de Kundin: Largo × Ancho × Profundidad × 0.327',
              style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.5)),
            ),
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
                      sideTitles: SideTitles(showTitles: true, reservedSize: 36),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) => [
                        for (final spot in touchedSpots)
                          () {
                            final m = volumePoints[spot.spotIndex].value;
                            final lines = <String>[
                              '${dateFmt.format(m.measuredAt)} · ${m.volumeCm3!.toStringAsFixed(2)} cm³',
                              if (m.volumeManual) '✎ Volumen ajustado manualmente',
                            ];
                            return LineTooltipItem(
                              lines.join('\n'),
                              const TextStyle(color: Colors.white, fontSize: 11),
                            );
                          }(),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (final e in volumePoints) FlSpot(e.key.toDouble(), e.value.volumeCm3!),
                      ],
                      isCurved: true,
                      color: KuraColors.infoBlue,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          final manual = volumePoints[index].value.volumeManual;
                          return FlDotCirclePainter(
                            radius: manual ? 5 : 3.5,
                            color: manual ? KuraColors.warning : KuraColors.infoBlue,
                            strokeColor: KuraColors.infoBlue,
                            strokeWidth: manual ? 1.5 : 0,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: KuraColors.infoBlue.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (volumePoints.any((e) => e.value.volumeManual)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.edit_note, size: 14, color: KuraColors.warning),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('✎ Punto(s) con volumen ajustado manualmente',
                        style: TextStyle(
                            fontSize: 11, color: KuraColors.warning, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Grafica de composicion del lecho (tejido) en el tiempo, como un
  /// grafico de lineas 100% apiladas: en cada visita las 4 bandas
  /// (granulacion/esfacelo/necrosis/epitelizacion, de abajo hacia arriba)
  /// siempre suman el 100% del alto del grafico, mostrando la proporcion
  /// real de cada clasificacion respecto del total del tejido.
  ///
  /// Tecnica (fl_chart no tiene un tipo "stacked" nativo para LineChart):
  /// se normalizan los 4 porcentajes de cada medicion para que sumen 100
  /// (por si la captura original no suma exactamente 100), se calculan 4
  /// lineas de suma acumulada (c0..c3, mas una linea base en 0) y se
  /// rellenan las 4 franjas entre lineas consecutivas con `betweenBarsData`.
  /// Lectura como "progreso": lo ideal es que la banda de
  /// granulacion/epitelizacion crezca y la de esfacelo/necrosis se reduzca.
  Widget _buildTissueCompositionCard(List<WoundMeasurement> measurements, DateFormat dateFmt) {
    Widget legendDot(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        );

    // Suma acumulada normalizada (0-100) por visita: [c0, c1, c2, c3] =
    // [granulacion, +esfacelo, +necrosis, +epitelizacion].
    final cumulative = <List<double>>[
      for (final m in measurements) bedCompositionCumulative(m),
    ];

    List<FlSpot> spotsFor(double Function(List<double> c) pick) => [
          for (var i = 0; i < measurements.length; i++) FlSpot(i.toDouble(), pick(cumulative[i])),
        ];

    LineChartBarData boundaryLine(List<FlSpot> spots) => LineChartBarData(
          spots: spots,
          isCurved: false,
          color: Colors.white.withOpacity(0.7),
          barWidth: 1,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 2.5,
              color: Colors.white,
              strokeColor: Colors.black.withOpacity(0.15),
              strokeWidth: 1,
            ),
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Composición del lecho en el tiempo (%)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                legendDot(KuraColors.success, 'Granulación'),
                legendDot(KuraColors.warning, 'Esfacelo'),
                legendDot(KuraColors.danger, 'Necrosis'),
                legendDot(KuraColors.infoBlue, 'Epitelización'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
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
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      // Se muestra un solo tooltip consolidado (con los 4
                      // valores REALES, no acumulados) anclado al primer
                      // punto tocado; el resto de los puntos tocados en la
                      // misma visita devuelven null para no repetir el
                      // tooltip 4 veces sobre la misma visita.
                      getTooltipItems: (touchedSpots) => [
                        for (var i = 0; i < touchedSpots.length; i++)
                          if (i != 0)
                            null
                          else
                            () {
                              final idx = touchedSpots[i].spotIndex;
                              if (idx < 0 || idx >= measurements.length) return null;
                              final m = measurements[idx];
                              final lines = <String>[
                                dateFmt.format(m.measuredAt),
                                'Granulación: ${m.granulationPct.toStringAsFixed(0)}%',
                                'Esfacelo: ${m.sloughPct.toStringAsFixed(0)}%',
                                'Necrosis: ${m.necrosisPct.toStringAsFixed(0)}%',
                                'Epitelización: ${m.epithelializationPct.toStringAsFixed(0)}%',
                              ];
                              return LineTooltipItem(
                                lines.join('\n'),
                                const TextStyle(color: Colors.white, fontSize: 11),
                              );
                            }(),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    // idx 0: linea base en 0, oculta (solo referencia
                    // inferior para el relleno de la primera franja).
                    LineChartBarData(
                      spots: spotsFor((c) => 0),
                      isCurved: false,
                      color: Colors.transparent,
                      barWidth: 0,
                      dotData: const FlDotData(show: false),
                      show: false,
                    ),
                    // idx 1..4: lineas de suma acumulada (limites entre
                    // franjas). Permanecen "show: true" (con trazo fino y
                    // sutil) para conservar el tooltip táctil en cada una.
                    boundaryLine(spotsFor((c) => c[0])),
                    boundaryLine(spotsFor((c) => c[1])),
                    boundaryLine(spotsFor((c) => c[2])),
                    boundaryLine(spotsFor((c) => c[3])),
                  ],
                  betweenBarsData: [
                    BetweenBarsData(fromIndex: 0, toIndex: 1, color: KuraColors.success),
                    BetweenBarsData(fromIndex: 1, toIndex: 2, color: KuraColors.warning),
                    BetweenBarsData(fromIndex: 2, toIndex: 3, color: KuraColors.danger),
                    BetweenBarsData(fromIndex: 3, toIndex: 4, color: KuraColors.infoBlue),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Busca, dentro de la serie real de mediciones, la mas antigua entre
/// [minWeeks] y [maxWeeks] semanas antes de [current] (ventana 2-4 semanas
/// del Protocolo de Desbridamiento SS13). No hay una cadencia de seguimiento
/// fija en los protocolos (fecha libre), asi que se toma la medicion mas
/// cercana a esa ventana entre las ya registradas; si ninguna medicion cae
/// en el rango, la regla de "sin avance" no se evalua (retorna null) en vez
/// de inventar un punto de comparacion.
WoundMeasurement? _referenceMeasurementForWindow(
  List<WoundMeasurement> measurements,
  WoundMeasurement current, {
  int minWeeks = 2,
  int maxWeeks = 4,
}) {
  final candidates = measurements.where((m) {
    if (m.id == current.id) return false;
    final weeksBefore = current.measuredAt.difference(m.measuredAt).inDays / 7;
    return weeksBefore >= minWeeks && weeksBefore <= maxWeeks;
  }).toList();
  if (candidates.isEmpty) return null;
  // La mas antigua dentro del rango, para comparar "misma ventana" contra
  // la mas reciente disponible en el rango (criterio conservador: si hubo
  // cualquier mejora parcial mas tarde dentro del rango, no se dispara).
  candidates.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  return candidates.first;
}

/// Foto "basal"/"actual" real de la herida (mas antigua / mas reciente en
/// `wound_photos` por taken_at), resuelta mediante signed URL (Supabase
/// Storage, bucket privado) o data URL (modo demo local). Si aun no existe
/// ninguna foto para la herida, muestra un placeholder explicito en vez de
/// un dato ficticio.
class _WoundPhotoCard extends StatelessWidget {
  final String label;
  final DateTime date;
  final WoundPhoto? photo;
  const _WoundPhotoCard({required this.label, required this.date, required this.photo});

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
        clipBehavior: Clip.antiAlias,
        child: photo == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.image_outlined, size: 32, color: KuraColors.darkText),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  const Text('Sin foto registrada', style: TextStyle(fontSize: 11)),
                ],
              )
            : FutureBuilder<String>(
                future: PhotoUploadService.resolveDisplayUrl(photo!.storagePath),
                builder: (context, snapshot) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (snapshot.hasData)
                        Image.network(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => const Center(
                            child: Icon(Icons.broken_image_outlined,
                                size: 32, color: KuraColors.darkText),
                          ),
                        )
                      else if (snapshot.hasError)
                        const Center(
                          child: Icon(Icons.broken_image_outlined,
                              size: 32, color: KuraColors.darkText),
                        )
                      else
                        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          color: Colors.black.withOpacity(0.55),
                          child: Column(
                            children: [
                              Text(label,
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w700)),
                              Text(DateFormat('dd/MM/yyyy').format(photo!.takenAt),
                                  style: const TextStyle(color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
