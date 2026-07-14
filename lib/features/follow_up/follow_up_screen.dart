import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/kura_sheehan_checkpoint.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/treatment_plan.dart';
import '../../models/wound.dart';
import '../../services/photo_upload_service.dart';

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

          final weeksSinceBaseline =
              current.measuredAt.difference(baseline.measuredAt).inDays ~/ 7;

          // Evaluacion clinica de la visita mas reciente (la misma consulta
          // de `current`), para alimentar los flags de penalizacion del
          // checkpoint. Se empata por consultationId cuando es posible; si
          // no hay match directo (dato legado sin consultation_id), se cae
          // a la evaluacion cuya consulta tenga la fecha mas reciente.
          WoundAssessment? latestAssessment;
          if (hasFollowUps) {
            final assessments = repo.listAssessmentsForWound(woundId);
            final matching =
                assessments.where((a) => a.consultationId == current.consultationId).toList();
            if (matching.isNotEmpty) {
              latestAssessment = matching.first;
            } else if (assessments.isNotEmpty) {
              final withDates = assessments
                  .map((a) => (
                        assessment: a,
                        date: repo.getConsultation(a.consultationId)?.visitDate ??
                            DateTime.fromMillisecondsSinceEpoch(0),
                      ))
                  .toList()
                ..sort((x, y) => x.date.compareTo(y.date));
              latestAssessment = withDates.last.assessment;
            }
          }

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
                  // TODO(clinico): deterioroDelLecho y aumentoDeExudado
                  // requieren una regla comparativa (actual vs. evaluacion
                  // anterior) todavia no definida. No se inventa la regla;
                  // se dejan en false (default) hasta que se defina.
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
                              Text('Checkpoint de Sheehan · Semana ${checkpoint.semana}',
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
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
    // El gauge refleja el % ajustado (con penalizaciones), que es el valor
    // real usado para tomar la decision — no el bruto.
    final pct = checkpoint.pctReduccionAjustada.clamp(0, 100) / 100;
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
