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
  // Respuestas elegidas por el profesional a las preguntas guía (en sesión, no
  // se persisten): clave = "<ruleId>::<índice>" -> opción elegida.
  final Map<String, String> _answers = {};

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

  Future<void> _logAction(
      DataRepository repo, PreventionAlert alert, PreventiveAction action) async {
    final session = ref.read(sessionProvider);
    await repo.logPreventiveAction(
      patientId: widget.patientId,
      organizationId: session.user?.organizationId,
      ruleId: alert.id,
      actionId: action.id,
      actionLabel: action.label,
      staffId: await _staffId(repo),
    );
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acción registrada.')),
      );
    }
  }

  /// Sección de alertas de una dimensión (LPP / complicación).
  Widget _alertSection(
      DataRepository repo, String title, List<PreventionAlert> alerts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ),
        ...alerts.map((a) => _alertCard(repo, a)),
      ],
    );
  }

  Widget _alertCard(DataRepository repo, PreventionAlert a) {
    final color = riskSeverityColor(a.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: KuraColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: KuraColors.darkText.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera con barra de color por severidad.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(a.message,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(a.severity.label,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.questions.isNotEmpty) ...[
                  _sectionLabel(Icons.help_outline, 'Qué preguntarte'),
                  const SizedBox(height: 8),
                  for (var i = 0; i < a.questions.length; i++)
                    _questionRow(a, i, a.questions[i]),
                ],
                if (a.actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionLabel(Icons.checklist_rtl,
                      a.escalation == null ? 'Acciones' : 'Prevención'),
                  const SizedBox(height: 6),
                  ...a.actions.map((act) => _actionRow(repo, a, act)),
                ],
                if (a.escalation != null && _hasAlarm(a)) ...[
                  const SizedBox(height: 12),
                  _escalationBlock(repo, a),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// true si el profesional respondió con la respuesta de alarma a alguna
  /// pregunta de la alerta.
  bool _hasAlarm(PreventionAlert a) {
    for (var i = 0; i < a.questions.length; i++) {
      final q = a.questions[i];
      if (q.alarm != null && _answers['${a.id}::$i'] == q.alarm) return true;
    }
    return false;
  }

  /// Conducta de escalamiento (se muestra cuando hay un hallazgo de alarma).
  Widget _escalationBlock(DataRepository repo, PreventionAlert a) {
    final esc = a.escalation!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: KuraColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KuraColors.danger.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.priority_high_rounded,
                  size: 16, color: KuraColors.danger),
              const SizedBox(width: 6),
              Text('CONDUCTA ANTE HALLAZGOS DE ALARMA',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: KuraColors.danger)),
            ],
          ),
          const SizedBox(height: 4),
          Text(esc.message, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          ...esc.actions.map((act) => _actionRow(repo, a, act)),
        ],
      ),
    );
  }

  Widget _sectionLabel(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: KuraColors.darkText.withOpacity(0.55)),
        const SizedBox(width: 6),
        Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: KuraColors.darkText.withOpacity(0.55))),
      ],
    );
  }

  Widget _questionRow(PreventionAlert a, int index, PreventionQuestion q) {
    final key = '${a.id}::$index';
    final selected = _answers[key];
    final isAlarm = q.alarm != null && selected == q.alarm;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isAlarm
            ? KuraColors.danger.withOpacity(0.07)
            : KuraColors.chipBg.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: isAlarm
            ? Border.all(color: KuraColors.danger.withOpacity(0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(q.text, style: const TextStyle(fontSize: 13)),
              ),
              if (isAlarm)
                const Padding(
                  padding: EdgeInsets.only(left: 6, top: 1),
                  child: Icon(Icons.priority_high_rounded,
                      size: 16, color: KuraColors.danger),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final opt in q.options)
                ChoiceChip(
                  label: Text(opt, style: const TextStyle(fontSize: 12)),
                  selected: selected == opt,
                  visualDensity: VisualDensity.compact,
                  selectedColor: (opt == q.alarm
                          ? KuraColors.danger
                          : KuraColors.primary)
                      .withOpacity(0.18),
                  labelStyle: TextStyle(
                    color: selected == opt
                        ? (opt == q.alarm
                            ? KuraColors.danger
                            : KuraColors.primary)
                        : null,
                    fontWeight:
                        selected == opt ? FontWeight.w700 : FontWeight.normal,
                  ),
                  onSelected: (_) => setState(() => _answers[key] = opt),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
      DataRepository repo, PreventionAlert a, PreventiveAction act) {
    final last = repo.lastAppliedAt(widget.patientId, a.id, act.id);
    final done = last != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: done
                  ? KuraColors.success
                  : KuraColors.darkText.withOpacity(0.35)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(act.label, style: const TextStyle(fontSize: 13)),
                if (done)
                  Text('Última: ${_dateFmt.format(last)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: KuraColors.darkText.withOpacity(0.55))),
              ],
            ),
          ),
          const SizedBox(width: 6),
          done
              ? OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: KuraColors.primary,
                      side: BorderSide(
                          color: KuraColors.primary.withOpacity(0.5))),
                  onPressed: () => _logAction(repo, a, act),
                  child: const Text('De nuevo'),
                )
              : FilledButton.tonal(
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _logAction(repo, a, act),
                  child: const Text('Registrar'),
                ),
        ],
      ),
    );
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
            final anyEscalation = result.alerts
                .any((a) => a.escalation != null && _hasAlarm(a));

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _RiskLevelBanner(level: result.level),
                if (anyEscalation) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: KuraColors.danger.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KuraColors.danger),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.priority_high_rounded,
                            color: KuraColors.danger),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Se detectaron signos de alarma. Revisa la conducta '
                            'de escalamiento en las alertas marcadas.',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: KuraColors.danger),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Genera/actualiza la agenda de tareas preventivas del paciente
                // a partir de las cadencias de las reglas que dispara su riesgo.
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_repeat_outlined),
                  label: const Text('Generar plan preventivo (agenda de tareas)'),
                  onPressed: () async {
                    final n = await repo.generatePreventiveTasksFor(
                      widget.patientId,
                      catalog,
                      organizationId: patient.organizationId,
                      createdBy: ref.read(sessionProvider).user?.id,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(n == 0
                            ? 'No hay actividades programables para el riesgo actual.'
                            : 'Se generaron $n tareas preventivas.'),
                        action: n == 0
                            ? null
                            : SnackBarAction(
                                label: 'Ver agenda',
                                onPressed: () => context.go('/prevention-agenda'),
                              ),
                      ),
                    );
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
                if (!result.hasAlerts)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: KuraColors.chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                        'Sin alertas preventivas con la información actual. '
                        'Captura la valoración de Braden y las comorbilidades '
                        'para una evaluación más completa.'),
                  )
                else ...[
                  if (result.lpp.isNotEmpty)
                    _alertSection(
                        repo, 'Riesgo de lesión por presión', result.lpp),
                  if (result.complicacion.isNotEmpty)
                    _alertSection(
                        repo, 'Riesgo de complicación', result.complicacion),
                ],
                const SizedBox(height: 16),
                Text(
                  'Alertas de apoyo a la decisión (borrador clínico). No '
                  'sustituyen el juicio profesional ni modifican el plan de '
                  'tratamiento.',
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

