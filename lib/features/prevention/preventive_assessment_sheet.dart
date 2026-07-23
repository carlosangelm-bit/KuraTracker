import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/risk/preventive_assessment.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../services/data_repository.dart';

/// Abre el cuestionario preventivo unificado (adaptativo) para un paciente.
/// Compartido por la ficha de riesgo (personal) y la vista del cuidador.
///
/// - `asCaregiver`: lo corre un cuidador. Si además `reportOnly` es true (paciente
///   CON lesión), el flujo es de REPORTE: el cuidador reporta signos y ve las
///   recomendaciones + qué vigilar, pero NO agenda (el profesional define el plan).
/// - Personal (asCaregiver=false): al agendar, las tareas se AUTO-ASIGNAN al
///   cuidador del paciente si lo hay (si no, quedan para el personal).
Future<bool?> showPreventiveAssessment(
  BuildContext context, {
  required String patientId,
  required String? organizationId,
  required bool asCaregiver,
  bool reportOnly = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AssessmentSheet(
      patientId: patientId,
      organizationId: organizationId,
      asCaregiver: asCaregiver,
      reportOnly: reportOnly,
    ),
  );
}

class _AssessmentSheet extends ConsumerStatefulWidget {
  final String patientId;
  final String? organizationId;
  final bool asCaregiver;
  final bool reportOnly;
  const _AssessmentSheet({
    required this.patientId,
    required this.organizationId,
    required this.asCaregiver,
    this.reportOnly = false,
  });

  @override
  ConsumerState<_AssessmentSheet> createState() => _AssessmentSheetState();
}

class _AssessmentSheetState extends ConsumerState<_AssessmentSheet> {
  final _answers = PreventiveAnswers();
  int _step = 0; // 0..5 preguntas; 6 = vista previa del plan
  bool _saving = false;

  // Total de pasos de pregunta (la 5b infección solo cuenta si hay herida).
  int get _questionSteps => _answers.hasWound == true ? 6 : 5;

  void _next() => setState(() => _step++);
  void _back() => setState(() => _step = _step > 0 ? _step - 1 : 0);

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final catalog = ref.watch(preventionRulesProvider).valueOrNull;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.reportOnly ? 'Reporte del cuidador' : 'Evaluación preventiva',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary)),
            const SizedBox(height: 2),
            Text(
              _step >= _questionSteps
                  ? (widget.reportOnly
                      ? 'Qué vigilar y cuándo avisar'
                      : 'Plan de acción sugerido')
                  : 'Paso ${_step + 1} de $_questionSteps',
              style: TextStyle(color: t.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: catalog == null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()))
                    : (_step >= _questionSteps
                        ? _preview(catalog, t)
                        : _questionForStep(_step, t)),
              ),
            ),
            if (_step > 0 && _step < _questionSteps) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: _back, child: const Text('Atrás')),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------- Preguntas (una por paso, adaptativo) --------------------
  Widget _questionForStep(int step, BrandTokens t) {
    switch (step) {
      case 0:
        return _choiceQuestion(
          '¿Cómo es la movilidad del paciente?',
          Movilidad.values
              .map((m) => _OptionSpec(m.label, () {
                    _answers.mobility = m;
                    _next();
                  }))
              .toList(),
        );
      case 1:
        return _yesNo(
          '¿La piel está húmeda por incontinencia o sudoración?',
          onYes: () {
            _answers.moisture = true;
            _next();
          },
          onNo: () {
            _answers.moisture = false;
            _next();
          },
        );
      case 2:
        return _yesNo(
          '¿El paciente come/se alimenta bien (más del 50% de sus alimentos)?',
          onYes: () {
            _answers.eatsWell = true;
            _next();
          },
          onNo: () {
            _answers.eatsWell = false;
            _next();
          },
        );
      case 3:
        return _yesNo(
          '¿Hay enrojecimiento que NO blanquea en zonas de apoyo (sacro, talones, etc.)?',
          onYes: () {
            _answers.nonBlanchingRedness = true;
            _next();
          },
          onNo: () {
            _answers.nonBlanchingRedness = false;
            _next();
          },
        );
      case 4:
        return _yesNo(
          '¿El paciente tiene alguna herida?',
          onYes: () {
            _answers.hasWound = true;
            _next();
          },
          onNo: () {
            _answers.hasWound = false;
            _answers.infectionSigns = null;
            _next();
          },
        );
      default: // 5: signos de infección (solo si hay herida)
        return _yesNo(
          '¿La herida muestra signos de infección (enrojecimiento creciente, pus, '
          'mal olor o fiebre)?',
          onYes: () {
            _answers.infectionSigns = true;
            _next();
          },
          onNo: () {
            _answers.infectionSigns = false;
            _next();
          },
        );
    }
  }

  Widget _choiceQuestion(String text, List<_OptionSpec> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        ...options.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: o.onTap,
                style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14)),
                child: Text(o.label, textAlign: TextAlign.left),
              ),
            )),
      ],
    );
  }

  Widget _yesNo(String text,
      {required VoidCallback onYes, required VoidCallback onNo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onYes,
                child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Sí')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: onNo,
                child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------- Vista previa del plan + confirmar --------------------
  Widget _preview(PreventionRulesCatalog catalog, BrandTokens t) {
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;
    final braden = repo?.latestRiskAssessment(widget.patientId)?.bradenScore;
    final plan = buildPreventivePlan(_answers, braden: braden, catalog: catalog);

    // Vigilancia de complicación por comorbilidades/infección (solo lectura).
    final complicationSigns = <String>[];
    if (repo != null) {
      final risk = repo.computeRisk(widget.patientId, catalog);
      for (final a in risk.complicacion) {
        complicationSigns.add(a.message);
      }
    }
    final allWatch = [...plan.watchSigns, ...complicationSigns];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En modo REPORTE (cuidador + lesión) NO se agenda: el profesional
        // define la agenda. Se muestran las recomendaciones/qué vigilar.
        if (widget.reportOnly)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: t.brandPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Tu agenda de cuidados la define el profesional. Este reporte le '
              'ayuda a dar seguimiento: si observas signos de alarma, avísale.',
              style: TextStyle(fontSize: 13, color: t.textPrimary),
            ),
          )
        else if (plan.activities.isEmpty)
          Text(
            'Sin actividades preventivas programadas para hoy. Revalorar si '
            'cambia la movilidad, aparece humedad o enrojecimiento.',
            style: TextStyle(color: t.textSecondary),
          )
        else ...[
          Text('Actividades a agendar',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: t.textSecondary)),
          const SizedBox(height: 6),
          ...plan.activities.map((s) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.check_circle_outline, color: t.brandPrimary),
                title: Text(s.title),
                subtitle: Text('cada ${s.everyHours} h'),
              )),
        ],
        if (allWatch.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Signos a vigilar',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: t.textSecondary)),
          const SizedBox(height: 6),
          ...allWatch.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.visibility_outlined,
                        size: 16, color: t.statusWarning),
                    const SizedBox(width: 8),
                    Expanded(child: Text(w, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              )),
        ]
        else if (widget.reportOnly) ...[
          const SizedBox(height: 8),
          Text('No se reportaron signos de alarma.',
              style: TextStyle(color: t.textSecondary, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(onPressed: _back, child: const Text('Atrás')),
            const Spacer(),
            if (widget.reportOnly)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Entendido'),
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.event_available_outlined),
                label: Text(plan.activities.isEmpty ? 'Cerrar' : 'Agendar plan'),
                onPressed:
                    _saving ? null : () => _confirm(repo, catalog, plan),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirm(
    DataRepository? repo,
    PreventionRulesCatalog catalog,
    PreventivePlan plan,
  ) async {
    if (repo == null) return;
    if (plan.activities.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    final me = ref.read(sessionProvider).user;
    // A quién se asignan las tareas:
    // - cuidador que se autoevalúa (paciente preventivo): a sí mismo.
    // - profesional: al cuidador asignado del paciente si lo hay (aparece en la
    //   agenda del cuidador); si no hay cuidador, sin asignar (lo ve el personal).
    String? assignee;
    var kind = 'staff';
    if (widget.asCaregiver) {
      assignee = me?.id;
      kind = 'cuidador';
    } else {
      final caregivers =
          repo.listCaregiverAssignments(patientId: widget.patientId);
      if (caregivers.isNotEmpty) {
        assignee = caregivers.first.caregiverProfileId;
        kind = 'cuidador';
      }
    }
    try {
      final n = await repo.generatePreventiveTasksFromSpecs(
        widget.patientId,
        plan.activities,
        horizonHours: catalog.cadenceHorizonHours,
        organizationId: widget.organizationId,
        assigneeProfileId: assignee,
        assigneeKind: kind,
        createdBy: me?.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan agendado: $n tareas.')),
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _OptionSpec {
  final String label;
  final VoidCallback onTap;
  const _OptionSpec(this.label, this.onTap);
}
