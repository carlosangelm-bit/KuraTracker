import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../engine/risk/braden_scale.dart';
import '../../models/app_user.dart';
import '../../models/patient.dart';
import '../../models/patient_admission.dart';
import '../../services/data_repository.dart';
import '../prevention/caregiver_plan_builder_sheet.dart';
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
    // Hospital: la valoración detona el plan preventivo esperado por nivel
    // (tareas sin dueño; el profesional puede ajustar). En otros centros no aplica.
    final catalog = ref.read(preventionRulesProvider).valueOrNull;
    if (catalog != null) {
      await repo.autoGeneratePlanIfHospital(
        widget.patientId,
        catalog,
        organizationId: session.user?.organizationId,
        createdBy: session.user?.id,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _admit(DataRepository repo) async {
    final floorCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final bedCtrl = TextEditingController();
    InputDecoration dec(String label, [String? hint]) => InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        );
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
            TextField(controller: floorCtrl, decoration: dec('Piso', 'Ej. 3')),
            const SizedBox(height: 8),
            TextField(
                controller: areaCtrl,
                decoration: dec('Área / servicio', 'Ej. Medicina Interna')),
            const SizedBox(height: 8),
            TextField(controller: bedCtrl, decoration: dec('Cama (opcional)')),
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
    String? t(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    await repo.admitPatient(
      patientId: widget.patientId,
      organizationId: session.user?.organizationId,
      floor: t(floorCtrl),
      area: t(areaCtrl),
      bed: t(bedCtrl),
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

  Future<void> _editCaregiverInstructions(
      DataRepository repo, String? organizationId) async {
    final ctrl = TextEditingController(
        text: repo.caregiverInstructionsFor(widget.patientId) ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Indicaciones para el cuidador'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText:
                  'Ej.: limpiar con solución fisiológica, no mojar el apósito, '
                  'avisar si hay fiebre o aumento de secreción.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    await repo.setCaregiverInstructions(
      patientId: widget.patientId,
      organizationId: organizationId,
      text: ctrl.text,
      updatedBy: ref.read(sessionProvider).user?.id,
    );
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
                // Selector DIRECTO de cuidados (el profesional marca las
                // indicaciones con su cadencia; puede omitir cuidados nocturnos).
                // Esto define/actualiza la agenda del cuidador.
                FilledButton.icon(
                  icon: const Icon(Icons.checklist_rtl),
                  label: const Text('Definir plan de cuidados'),
                  onPressed: () async {
                    final agendada = await showCaregiverPlanBuilder(
                      context,
                      patientId: widget.patientId,
                      organizationId: patient.organizationId,
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
                const SizedBox(height: 8),
                // Indicaciones libres del profesional para el cuidador (0044).
                _InfoTile(
                  icon: Icons.sticky_note_2_outlined,
                  title: 'Indicaciones para el cuidador',
                  body: (repo.caregiverInstructionsFor(widget.patientId) ??
                              '')
                          .trim()
                          .isEmpty
                      ? 'Sin indicaciones. Deja el set de cuidados para el '
                          'cuidador (según diagnóstico).'
                      : repo.caregiverInstructionsFor(widget.patientId)!,
                  action: TextButton(
                    onPressed: () =>
                        _editCaregiverInstructions(repo, patient.organizationId),
                    child: const Text('Editar'),
                  ),
                ),
                const SizedBox(height: 16),
                _CompliancePanel(repo: repo, patient: patient),
                const SizedBox(height: 16),
                _PatientAuditLog(repo: repo, patientId: widget.patientId),
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

/// Cumplimiento preventivo del paciente en la ventana (turno/24 h): global +
/// por tipo de actividad. Solo se muestra si hay plan (actividades esperadas).
class _CompliancePanel extends StatelessWidget {
  final DataRepository repo;
  final Patient patient;
  const _CompliancePanel({required this.repo, required this.patient});

  @override
  Widget build(BuildContext context) {
    final c = repo.preventiveCompliance(patient.id,
        organizationId: patient.organizationId);
    if (!c.hasExpected) return const SizedBox.shrink();
    Color pctColor(int p) => p >= 85
        ? KuraColors.success
        : p >= 60
            ? KuraColors.warning
            : KuraColors.danger;
    final types = [...c.byType]..sort((a, b) => a.title.compareTo(b.title));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Cumplimiento preventivo',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text('${c.globalPct}%',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: pctColor(c.globalPct))),
              ],
            ),
            Text('${c.doneTotal}/${c.expectedTotal} actividades realizadas (ventana actual)',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            ...types.map((tt) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(tt.title,
                                  style: const TextStyle(fontSize: 13))),
                          Text('${tt.done}/${tt.expected} · ${tt.pct}%',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: pctColor(tt.pct))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: tt.expected == 0 ? 0 : tt.done / tt.expected,
                          minHeight: 5,
                          backgroundColor: KuraColors.chipBg,
                          color: pctColor(tt.pct),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Bitácora del paciente (auditoría): cronología colapsable de valoraciones,
/// actividades realizadas y eventos adversos — qué, cuándo y quién.
class _PatientAuditLog extends StatelessWidget {
  final DataRepository repo;
  final String patientId;
  const _PatientAuditLog({required this.repo, required this.patientId});

  @override
  Widget build(BuildContext context) {
    // Resolución de "quién" (staff o usuario) por id.
    final staffById = {for (final s in repo.listStaff()) s.id: s.fullName};
    final userById = {for (final u in repo.listUsers()) u.id: u.fullName};
    String who(String? id) =>
        id == null ? '' : (staffById[id] ?? userById[id] ?? '');

    final entries = <(DateTime, IconData, String, String)>[];
    for (final r in repo.listRiskAssessments(patientId)) {
      entries.add((
        r.assessedAt,
        Icons.monitor_heart_outlined,
        'Valoración Braden${r.bradenScore != null ? ' ${r.bradenScore}' : ''}',
        who(r.assessedBy),
      ));
    }
    for (final a in repo.listPreventiveActions(patientId)) {
      entries.add((a.appliedAt, Icons.check_circle_outline, a.actionLabel, who(a.appliedBy)));
    }
    for (final e in repo.listAdverseEventsForPatient(patientId)) {
      entries.add((e.occurredAt, Icons.warning_amber_rounded,
          'Evento adverso: ${e.type}', who(e.staffId)));
    }
    entries.sort((a, b) => b.$1.compareTo(a.$1));

    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Card(
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: const Icon(Icons.history),
          title: const Text('Bitácora del paciente',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${entries.length} registros'),
          children: entries.isEmpty
              ? [const Padding(padding: EdgeInsets.all(8), child: Text('Sin registros.'))]
              : entries
                  .map((e) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(e.$2, size: 18, color: KuraColors.primary),
                        title: Text(e.$3, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          '${fmt.format(e.$1)}${e.$4.isNotEmpty ? ' · ${e.$4}' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ))
                  .toList(),
        ),
      ),
    );
  }
}
