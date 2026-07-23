import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../engine/risk/braden_scale.dart';
import '../../models/app_user.dart';
import '../../models/patient_admission.dart';
import '../../services/data_repository.dart';
import '../prevention/preventive_assessment_sheet.dart';
import 'risk_theme.dart';

/// Ficha de riesgo de un paciente (módulo de Prevención). Muestra el nivel de
/// riesgo, las alertas preventivas (LPP / complicación) con su recomendación,
/// la última valoración de Braden y el internamiento. Permite valorar riesgo
/// e ingresar/egresar. Capa DOCUMENTAL: no cambia el motor de tratamiento.
class PatientRiskScreen extends ConsumerStatefulWidget {
  final String patientId;
  const PatientRiskScreen({super.key, required this.patientId});

  @override
  ConsumerState<PatientRiskScreen> createState() => _PatientRiskScreenState();
}

class _PatientRiskScreenState extends ConsumerState<PatientRiskScreen> {
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  Future<String?> _staffId(DataRepository repo) async {
    final session = ref.read(sessionProvider);
    var id = session.user?.staffId;
    if (id == null && session.user?.role == AppRole.admin) {
      id = await repo.ensureAdminStaffId(session.user!);
    }
    return id;
  }

  /// Formulario de Braden por subescalas: el profesional elige una opción por
  /// ítem y la app calcula el total y la banda de riesgo. Guarda el total
  /// (braden_score) y las subescalas (braden_subscores).
  Future<void> _assessBraden(DataRepository repo, BradenScale scale) async {
    final selections = <String, int>{};
    final notesCtrl = TextEditingController();

    final result = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final answered = selections.length == scale.items.length;
          final total =
              selections.values.fold<int>(0, (a, b) => a + b);
          final band = answered ? scale.riskLabelFor(total) : null;
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 4,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Valoración de Braden',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text('Elige una opción por ítem; el total se calcula solo.',
                      style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in scale.items) ...[
                            Text(item.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final o in item.options)
                                  ChoiceChip(
                                    label: Text('${o.score} · ${o.label}',
                                        style: const TextStyle(fontSize: 12)),
                                    selected: selections[item.id] == o.score,
                                    selectedColor:
                                        KuraColors.primary.withOpacity(0.16),
                                    onSelected: (_) => setSheet(
                                        () => selections[item.id] = o.score),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          answered
                              ? 'Total: $total  ·  ${band ?? ''}'
                              : 'Faltan ${scale.items.length - selections.length} ítem(s)',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: answered
                                  ? KuraColors.primary
                                  : KuraColors.darkText.withOpacity(0.6)),
                        ),
                      ),
                      FilledButton(
                        onPressed: answered
                            ? () => Navigator.of(ctx).pop(
                                Map<String, int>.from(selections))
                            : null,
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

    if (result == null || !mounted) return;
    final total = result.values.fold<int>(0, (a, b) => a + b);
    final session = ref.read(sessionProvider);
    await repo.addRiskAssessment(
      patientId: widget.patientId,
      organizationId: session.user?.organizationId,
      bradenScore: total,
      bradenSubscores: result,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      staffId: await _staffId(repo),
    );
    if (mounted) setState(() {});
  }

  Future<void> _admit(DataRepository repo) async {
    final unitCtrl = TextEditingController();
    final bedCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Registrar internamiento',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: unitCtrl,
              decoration: const InputDecoration(
                labelText: 'Unidad / servicio',
                hintText: 'Ej. Medicina Interna',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bedCtrl,
              decoration: const InputDecoration(
                labelText: 'Cama (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Ingresar'),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final session = ref.read(sessionProvider);
    await repo.admitPatient(
      patientId: widget.patientId,
      organizationId: session.user?.organizationId,
      unit: unitCtrl.text.trim().isEmpty ? null : unitCtrl.text.trim(),
      bed: bedCtrl.text.trim().isEmpty ? null : bedCtrl.text.trim(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _discharge(DataRepository repo, PatientAdmission a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Egresar paciente'),
        content: const Text('¿Registrar el egreso de este internamiento?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Egresar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await repo.dischargePatient(a.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final rulesAsync = ref.watch(preventionRulesProvider);
    final scale = ref.watch(bradenScaleProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver al paciente',
          onPressed: () => context.go('/patients/${widget.patientId}'),
        ),
        title: const Text('Prevención y riesgo'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) => rulesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error al cargar reglas: $e')),
          data: (catalog) {
            final patient = repo.getPatient(widget.patientId);
            if (patient == null) {
              return const Center(child: Text('Paciente no encontrado.'));
            }
            final result = repo.computeRisk(widget.patientId, catalog);
            final admission = repo.activeAdmission(widget.patientId);
            final braden = repo.latestRiskAssessment(widget.patientId);

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _RiskLevelBanner(level: result.level),
                const SizedBox(height: 16),
                // Cuestionario preventivo unificado: un solo flujo simple que
                // produce el plan concreto y lo agenda.
                FilledButton.icon(
                  icon: const Icon(Icons.assignment_turned_in_outlined),
                  label: const Text('Evaluación preventiva'),
                  onPressed: () async {
                    final agendada = await showPreventiveAssessment(
                      context,
                      patientId: widget.patientId,
                      organizationId: patient.organizationId,
                      asCaregiver: false,
                    );
                    if (!context.mounted) return;
                    if (agendada == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Plan agendado.'),
                          action: SnackBarAction(
                            label: 'Ver agenda',
                            onPressed: () => context.go('/prevention-agenda'),
                          ),
                        ),
                      );
                    }
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                _InfoTile(
                  icon: Icons.local_hotel_outlined,
                  title: 'Internamiento',
                  body: admission == null
                      ? 'No internado'
                      : '${admission.unit ?? 'Sin unidad'}'
                          '${admission.bed != null ? ' · Cama ${admission.bed}' : ''}'
                          '\nIngreso: ${_dateFmt.format(admission.admittedAt)}',
                  action: admission == null
                      ? TextButton(
                          onPressed: () => _admit(repo),
                          child: const Text('Ingresar'))
                      : TextButton(
                          onPressed: () => _discharge(repo, admission),
                          child: const Text('Egresar')),
                ),
                const SizedBox(height: 8),
                _InfoTile(
                  icon: Icons.monitor_heart_outlined,
                  title: 'Valoración de Braden',
                  body: braden?.bradenScore == null
                      ? 'Sin valoración registrada'
                      : 'Braden ${braden!.bradenScore}'
                          '${scale?.riskLabelFor(braden.bradenScore!) != null ? ' · ${scale!.riskLabelFor(braden.bradenScore!)}' : ''}'
                          ' · ${_dateFmt.format(braden.assessedAt)}',
                  action: TextButton(
                    onPressed:
                        scale == null ? null : () => _assessBraden(repo, scale),
                    child: const Text('Valorar'),
                  ),
                ),
                const SizedBox(height: 20),
                // Signos a vigilar por comorbilidades/complicación (solo lectura):
                // NO son tareas de la agenda; son qué observar. Las actividades
                // concretas salen del cuestionario ("Evaluación preventiva").
                if (result.complicacion.isNotEmpty) ...[
                  _WatchSignsCard(alerts: result.complicacion),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Apoyo a la decisión (borrador clínico). No sustituye el juicio '
                  'profesional ni modifica el plan de tratamiento.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: KuraColors.darkText.withOpacity(0.6)),
                ),
                const SizedBox(height: 40),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RiskLevelBanner extends StatelessWidget {
  final RiskLevel level;
  const _RiskLevelBanner({required this.level});

  @override
  Widget build(BuildContext context) {
    final color = riskLevelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: color),
          const SizedBox(width: 12),
          Text(level.label,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: color)),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const _InfoTile(
      {required this.icon,
      required this.title,
      required this.body,
      this.action});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: KuraColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(body, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}


/// Tarjeta compacta de "Signos a vigilar" (solo lectura): mensajes de las
/// alertas de complicación (comorbilidades / infección IWII). NO son tareas de
/// la agenda; son qué observar. Las actividades concretas salen del
/// cuestionario "Evaluación preventiva".
class _WatchSignsCard extends StatelessWidget {
  final List<PreventionAlert> alerts;
  const _WatchSignsCard({required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.visibility_outlined, size: 18),
                SizedBox(width: 8),
                Text('Signos a vigilar',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            ...alerts.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.circle,
                          size: 7, color: riskSeverityColor(a.severity)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(a.message,
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
