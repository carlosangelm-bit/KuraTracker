import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/adverse_event.dart';
import '../../services/data_repository.dart';

/// Color de la marca de gravedad (semáforo clínico). Centinela usa el mismo
/// rojo que grave pero se distingue con la marca de alerta de reporte.
Color adverseSeverityColor(AdverseEventSeverity s) {
  switch (s) {
    case AdverseEventSeverity.leve:
      return KuraColors.success;
    case AdverseEventSeverity.moderado:
      return KuraColors.warning;
    case AdverseEventSeverity.grave:
    case AdverseEventSeverity.centinela:
      return KuraColors.danger;
  }
}

/// Bitácora de eventos adversos de un paciente (Protocolo "Manejo de eventos
/// adversos"). Lista por paciente + marca de alerta y recordatorio de reporte
/// ≤24 h para los eventos centinela pendientes.
class AdverseEventsScreen extends ConsumerStatefulWidget {
  final String patientId;
  const AdverseEventsScreen({super.key, required this.patientId});

  @override
  ConsumerState<AdverseEventsScreen> createState() =>
      _AdverseEventsScreenState();
}

class _AdverseEventsScreenState extends ConsumerState<AdverseEventsScreen> {
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  Future<void> _markReported(AdverseEvent event) async {
    final repo = await DataRepository.instance();
    await repo.markAdverseEventReported(event.id);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evento marcado como reportado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eventos adversos'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add_circle_outline, color: KuraColors.primary),
            label: const Text('Registrar evento',
                style: TextStyle(color: KuraColors.primary)),
            onPressed: () =>
                context.go('/patients/${widget.patientId}/adverse-events/new'),
          ),
        ],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final events = repo.listAdverseEventsForPatient(widget.patientId);
          if (events.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('Sin eventos adversos registrados para este paciente.'),
              ),
            );
          }
          final now = DateTime.now();
          final pendientes = events.where((e) => e.needsReport).toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (pendientes.isNotEmpty) ...[
                _CentinelaAlertBanner(count: pendientes.length),
                const SizedBox(height: 16),
              ],
              ...events.map((e) => _AdverseEventCard(
                    event: e,
                    now: now,
                    dateFmt: _dateFmt,
                    onMarkReported: () => _markReported(e),
                  )),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

/// Banner de alerta cuando hay eventos centinela pendientes de reporte.
class _CentinelaAlertBanner extends StatelessWidget {
  final int count;
  const _CentinelaAlertBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KuraColors.danger.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KuraColors.danger.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: KuraColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? 'Hay 1 evento centinela PENDIENTE de reporte a la autoridad (≤24 h).'
                  : 'Hay $count eventos centinela PENDIENTES de reporte a la autoridad (≤24 h).',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: KuraColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdverseEventCard extends StatelessWidget {
  final AdverseEvent event;
  final DateTime now;
  final DateFormat dateFmt;
  final VoidCallback onMarkReported;

  const _AdverseEventCard({
    required this.event,
    required this.now,
    required this.dateFmt,
    required this.onMarkReported,
  });

  @override
  Widget build(BuildContext context) {
    final color = adverseSeverityColor(event.severity);
    final overdue = event.isReportOverdue(now);
    final signs = event.alarmSigns.map((s) => s.label).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.type,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _SeverityChip(severity: event.severity, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Ocurrió: ${dateFmt.format(event.occurredAt.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (signs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: signs
                    .map((label) => Chip(
                          label: Text(label),
                          backgroundColor: KuraColors.chipBg,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
            if ((event.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _LabeledText(label: 'Descripción', value: event.description!),
            ],
            if ((event.actionsTaken ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _LabeledText(label: 'Acciones tomadas', value: event.actionsTaken!),
            ],
            if ((event.evolution ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _LabeledText(label: 'Evolución', value: event.evolution!),
            ],
            // Estado de reporte (solo relevante para centinela).
            if (event.isCentinela) ...[
              const SizedBox(height: 12),
              _ReportStatusRow(
                event: event,
                now: now,
                overdue: overdue,
                dateFmt: dateFmt,
                onMarkReported: onMarkReported,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportStatusRow extends StatelessWidget {
  final AdverseEvent event;
  final DateTime now;
  final bool overdue;
  final DateFormat dateFmt;
  final VoidCallback onMarkReported;

  const _ReportStatusRow({
    required this.event,
    required this.now,
    required this.overdue,
    required this.dateFmt,
    required this.onMarkReported,
  });

  @override
  Widget build(BuildContext context) {
    if (event.isReported) {
      return Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: KuraColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reportado el ${dateFmt.format(event.reportedAt!.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    // Pendiente de reporte: mostrar vencimiento y acción de marcar reportado.
    final deadline = event.reportDeadline.toLocal();
    final msg = overdue
        ? 'Reporte VENCIDO (límite ${dateFmt.format(deadline)}).'
        : 'Reportar antes de ${dateFmt.format(deadline)} (≤24 h).';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KuraColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(overdue ? Icons.error_outline : Icons.schedule,
              size: 18, color: KuraColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: KuraColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          TextButton(
            onPressed: onMarkReported,
            child: const Text('Marcar reportado'),
          ),
        ],
      ),
    );
  }
}

class _SeverityChip extends StatelessWidget {
  final AdverseEventSeverity severity;
  final Color color;
  const _SeverityChip({required this.severity, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        severity.label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _LabeledText extends StatelessWidget {
  final String label;
  final String value;
  const _LabeledText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: KuraColors.darkText)),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
