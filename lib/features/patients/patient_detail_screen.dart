import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/patient.dart';
import '../../models/wound.dart';
import '../../models/consultation.dart';
import '../../services/data_repository.dart';

class PatientDetailScreen extends ConsumerStatefulWidget {
  final String patientId;
  const PatientDetailScreen({super.key, required this.patientId});

  @override
  ConsumerState<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  final _dateFmt = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final patient = repo.getPatient(widget.patientId);
          if (patient == null) {
            return const Center(child: Text('Paciente no encontrado.'));
          }
          final wounds = repo.listWoundsForPatient(patient.id);
          final consultations = repo.listConsultationsForPatient(patient.id);
          final comorbidities = repo.listComorbidities(patient.id);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text(patient.fullName),
                pinned: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Nueva consulta',
                    onPressed: () =>
                        context.go('/patients/${patient.id}/consultation/new'),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _PatientHeaderCard(patient: patient, dateFmt: _dateFmt),
                    const SizedBox(height: 16),
                    if (comorbidities.isNotEmpty) _ComorbidityCard(comorbidities: comorbidities),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Heridas',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Registrar herida'),
                          onPressed: () =>
                              context.go('/patients/${patient.id}/consultation/new'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (wounds.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Sin heridas registradas.'),
                      )
                    else
                      ...wounds.map((w) => _WoundCard(
                            patientId: patient.id,
                            wound: w,
                            repo: repo,
                          )),
                    const SizedBox(height: 24),
                    Text('Historial de consultas',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    if (consultations.isEmpty)
                      const Text('Sin consultas registradas.')
                    else
                      ...consultations.map((c) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () => context
                                  .go('/patients/${widget.patientId}/consultation/${c.id}'),
                              leading: Icon(
                                c.visitType == VisitType.valoracion
                                    ? Icons.assignment_outlined
                                    : Icons.update,
                                color: KuraColors.primary,
                              ),
                              title: Text(c.visitType.label),
                              subtitle: Text(_dateFmt.format(c.visitDate)),
                              trailing: c.isDraft
                                  ? const Chip(
                                      label: Text('Borrador'),
                                      backgroundColor: KuraColors.chipBg,
                                    )
                                  : const Icon(Icons.chevron_right, size: 18),
                            ),
                          )),
                    const SizedBox(height: 40),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PatientHeaderCard extends StatelessWidget {
  final Patient patient;
  final DateFormat dateFmt;
  const _PatientHeaderCard({required this.patient, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(patient.folio),
                  backgroundColor: KuraColors.primary.withOpacity(0.1),
                  labelStyle: const TextStyle(
                      color: KuraColors.primary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                if (patient.fragilePatient)
                  const Chip(
                    label: Text('Frágil'),
                    backgroundColor: Color(0x1AE8A93A),
                    avatar: Icon(Icons.priority_high, size: 16, color: KuraColors.warning),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _InfoItem(label: 'Edad', value: '${patient.age ?? '-'} años'),
                _InfoItem(label: 'Sexo', value: patient.sex ?? '-'),
                _InfoItem(
                  label: 'Movilidad',
                  value: patient.mobility ?? '-',
                ),
                _InfoItem(
                  label: 'Cuidador',
                  value: patient.hasIdentifiedCaregiver
                      ? (patient.caregiverName ?? 'Identificado')
                      : 'No identificado',
                ),
                if (patient.ekareExternalId != null)
                  _InfoItem(label: 'eKare ID', value: patient.ekareExternalId!),
              ],
            ),
            if (patient.backgroundNotes != null && patient.backgroundNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text('Antecedentes',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KuraColors.darkText.withOpacity(0.6))),
              const SizedBox(height: 4),
              Text(patient.backgroundNotes!),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.5))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ComorbidityCard extends StatelessWidget {
  final List<PatientComorbidity> comorbidities;
  const _ComorbidityCard({required this.comorbidities});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Comorbilidades', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: comorbidities.map((c) {
                Color color;
                switch (c.status) {
                  case ComorbilidadEstado.presente:
                    color = KuraColors.danger;
                    break;
                  case ComorbilidadEstado.negado:
                    color = KuraColors.success;
                    break;
                  case ComorbilidadEstado.noEvaluado:
                    color = KuraColors.darkText.withOpacity(0.4);
                    break;
                }
                return Chip(
                  label: Text(c.code.label, style: const TextStyle(fontSize: 12)),
                  avatar: Icon(Icons.circle, size: 10, color: color),
                  backgroundColor: KuraColors.chipBg,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WoundCard extends StatelessWidget {
  final String patientId;
  final Wound wound;
  final DataRepository repo;
  const _WoundCard({required this.patientId, required this.wound, required this.repo});

  @override
  Widget build(BuildContext context) {
    final measurements = repo.listMeasurementsForWound(wound.id);
    final latest = measurements.isNotEmpty ? measurements.last : null;
    final recs = repo.listRecommendationsForWound(wound.id);
    final lastRec = recs.isNotEmpty ? recs.last : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: KuraColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.healing, color: KuraColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(wound.etiology.label,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (wound.subtype != null)
                        Text(wound.subtype!, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                if (lastRec != null)
                  _ScenarioBadge(scenario: lastRec['dominant_scenario'] as String),
              ],
            ),
            if (latest != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _MiniStat(label: 'Área', value: '${latest.areaCm2.toStringAsFixed(1)} cm²'),
                  _MiniStat(label: 'Profundidad', value: '${latest.depthCm} cm'),
                  _MiniStat(
                      label: 'Necrosis+Esfacelo',
                      value:
                          '${(latest.necrosisPct + latest.sloughPct).toStringAsFixed(0)}%'),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.show_chart, size: 18),
                  label: const Text('Seguimiento'),
                  onPressed: () =>
                      context.go('/patients/$patientId/wound/${wound.id}/follow-up'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Nueva valoración'),
                  onPressed: () =>
                      context.go('/patients/$patientId/wound/${wound.id}/capture'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: KuraColors.darkText),
        children: [
          TextSpan(text: '$label: ', style: TextStyle(color: KuraColors.darkText.withOpacity(0.5))),
          TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ScenarioBadge extends StatelessWidget {
  final String scenario;
  const _ScenarioBadge({required this.scenario});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (scenario) {
      case 'A':
        color = KuraColors.scenarioA;
        break;
      case 'B':
        color = KuraColors.scenarioB;
        break;
      default:
        color = KuraColors.scenarioC;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('Escenario $scenario',
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
