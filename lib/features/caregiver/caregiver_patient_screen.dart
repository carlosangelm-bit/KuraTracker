import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart' show EtiologiaLabel;
import '../../models/wound.dart';
import '../../services/data_repository.dart';
import '../prevention/preventive_assessment_sheet.dart';

/// Pantalla del monitor de un paciente (cuidador con varios pacientes): AppBar
/// con volver + el monitor. Cuando el cuidador tiene UN solo paciente, el
/// monitor se muestra directo en el home (sin esta pantalla).
class CaregiverPatientScreen extends StatelessWidget {
  final String patientId;
  const CaregiverPatientScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/caregiver')),
        title: const Text('Paciente'),
      ),
      body: CaregiverPatientMonitor(patientId: patientId),
    );
  }
}

/// Monitor del paciente para el cuidador (SOLO LECTURA de lo clínico):
/// indicaciones del profesional, recomendaciones del centro, evolución de la
/// herida y contacto/cita. Las TAREAS no van aquí: viven en la vista de agenda
/// (día/semana). Reutilizable como pantalla o embebido en el home.
class CaregiverPatientMonitor extends ConsumerStatefulWidget {
  final String patientId;
  const CaregiverPatientMonitor({super.key, required this.patientId});

  @override
  ConsumerState<CaregiverPatientMonitor> createState() =>
      _CaregiverPatientMonitorState();
}

class _CaregiverPatientMonitorState
    extends ConsumerState<CaregiverPatientMonitor> {
  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;
    final t = BrandTokens.of(context);

    return repoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (repo) {
        final patient = repo.getPatient(widget.patientId);
        if (patient == null) {
          return const Center(child: Text('Paciente no disponible.'));
        }
        final wounds = repo
            .listWoundsForPatient(widget.patientId)
            .where((w) => w.isActive)
            .toList();
        final nextAppt = repo.nextManualAppointmentForPatient(widget.patientId);
        final center = repo.organizationById(user?.organizationId);
        final instructions = repo.caregiverInstructionsFor(widget.patientId);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
            Text(patient.fullName,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),

            // Paciente CON lesión → REPORTE (el profesional define la agenda).
            // Paciente sin lesión (preventivo) → el cuidador puede evaluar.
            FilledButton.icon(
              icon: Icon(wounds.isNotEmpty
                  ? Icons.fact_check_outlined
                  : Icons.assignment_turned_in_outlined),
              label: Text(wounds.isNotEmpty
                  ? 'Reportar signos / recomendaciones'
                  : 'Evaluación preventiva'),
              onPressed: () async {
                final r = await showPreventiveAssessment(
                  context,
                  patientId: widget.patientId,
                  organizationId: patient.organizationId,
                  asCaregiver: true,
                  reportOnly: wounds.isNotEmpty,
                );
                if (r == true && mounted) setState(() {});
              },
            ),
            const SizedBox(height: 16),

            if ((instructions ?? '').trim().isNotEmpty)
              _SectionCard(
                icon: Icons.sticky_note_2_outlined,
                title: 'Indicaciones del profesional',
                child: Text(instructions!),
              ),

            _SectionCard(
              icon: Icons.assignment_outlined,
              title: 'Recomendaciones del centro',
              child: wounds.isEmpty
                  ? const Text('Sin heridas activas registradas.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: wounds
                          .map((w) => _WoundRecommendation(repo: repo, wound: w))
                          .toList(),
                    ),
            ),

            _SectionCard(
              icon: Icons.trending_up,
              title: 'Evolución de la herida',
              child: wounds.isEmpty
                  ? const Text('Sin mediciones registradas.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: wounds
                          .map((w) => _WoundEvolution(repo: repo, wound: w))
                          .toList(),
                    ),
            ),

            _SectionCard(
              icon: Icons.event_available_outlined,
              title: 'Cita y contacto',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nextAppt == null
                      ? 'Sin próxima cita agendada.'
                      : 'Próxima cita: ${nextAppt.datetime.toIso8601String().substring(0, 16).replaceFirst("T", " ")}'
                          '${nextAppt.title != null ? " · ${nextAppt.title}" : ""}'),
                  const SizedBox(height: 4),
                  Text('Centro: ${center?.name ?? "—"}',
                      style: TextStyle(color: t.textSecondary)),
                  if (patient.caregiverPhone != null &&
                      patient.caregiverPhone!.isNotEmpty)
                    Text('Contacto: ${patient.caregiverPhone}',
                        style: TextStyle(color: t.textSecondary)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _SectionCard(
      {required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: t.brandPrimary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _WoundRecommendation extends StatelessWidget {
  final DataRepository repo;
  final Wound wound;
  const _WoundRecommendation({required this.repo, required this.wound});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final recs = repo.listRecommendationsForWound(wound.id);
    final latest = recs.isEmpty ? null : recs.first;
    final scenario = latest?['dominant_scenario'] as String?;
    final notes = latest?['clinician_notes'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(wound.etiology.label,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (scenario != null)
            Text('Escenario del centro: $scenario',
                style: TextStyle(color: t.textSecondary, fontSize: 13)),
          if (notes != null && notes.isNotEmpty)
            Text(notes, style: const TextStyle(fontSize: 13)),
          if (latest == null)
            Text('Sin recomendaciones registradas todavía.',
                style: TextStyle(color: t.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _WoundEvolution extends StatelessWidget {
  final DataRepository repo;
  final Wound wound;
  const _WoundEvolution({required this.repo, required this.wound});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final ms = repo.listMeasurementsForWound(wound.id);
    final latest = ms.isEmpty ? null : ms.last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(wound.etiology.label,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (latest != null)
            Text(
              'Última medición: ${latest.areaCm2.toStringAsFixed(1)} cm²'
              '${latest.volumeCm3 != null ? " · ${latest.volumeCm3!.toStringAsFixed(1)} cm³" : ""}'
              ' (${latest.measuredAt.toIso8601String().substring(0, 10)})',
              style: TextStyle(color: t.textSecondary, fontSize: 13),
            )
          else
            Text('Sin mediciones registradas.',
                style: TextStyle(color: t.textSecondary, fontSize: 13)),
          if (ms.length > 1)
            Text('${ms.length} mediciones en el seguimiento.',
                style: TextStyle(color: t.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
