import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../models/center_type.dart';
import '../../services/data_repository.dart';

/// Selector DIRECTO de cuidados para el PROFESIONAL (no un cuestionario para
/// legos): muestra todas las indicaciones posibles con su cadencia; el
/// profesional marca las que aplican y agenda el plan del cuidador. Permite
/// omitir los cuidados nocturnos.
Future<bool?> showCaregiverPlanBuilder(
  BuildContext context, {
  required String patientId,
  required String? organizationId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PlanBuilderSheet(
      patientId: patientId,
      organizationId: organizationId,
    ),
  );
}

class _PlanBuilderSheet extends ConsumerStatefulWidget {
  final String patientId;
  final String? organizationId;
  const _PlanBuilderSheet({required this.patientId, required this.organizationId});

  @override
  ConsumerState<_PlanBuilderSheet> createState() => _PlanBuilderSheetState();
}

class _PlanBuilderSheetState extends ConsumerState<_PlanBuilderSheet> {
  final Set<String> _selected = {};
  bool _skipNight = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final catalog = ref.watch(preventionRulesProvider).valueOrNull;
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;

    // Catálogo de indicaciones ordenado por frecuencia (más frecuentes arriba).
    final items = (catalog?.cadences.entries.toList() ?? [])
      ..sort((a, b) => a.value.everyHours.compareTo(b.value.everyHours));

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
            Text('Plan de cuidados para el cuidador',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: t.textPrimary)),
            const SizedBox(height: 2),
            Text('Marca las indicaciones; la frecuencia se muestra a la derecha.',
                style: TextStyle(color: t.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            if (catalog == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...items.map((e) {
                        final id = e.key;
                        final cad = e.value;
                        final on = _selected.contains(id);
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: on,
                          onChanged: (v) => setState(() =>
                              v == true ? _selected.add(id) : _selected.remove(id)),
                          title: Text(cad.title),
                          secondary: Chip(
                            label: Text('cada ${cad.everyHours} h',
                                style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      }),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _skipNight,
                        onChanged: (v) => setState(() => _skipNight = v),
                        title: const Text('Omitir cuidados nocturnos'),
                        subtitle: const Text('No se agendan tareas entre 22:00 y 06:00'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar')),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text('Agendar (${_selected.length})'),
                  onPressed: (_saving || _selected.isEmpty || repo == null || catalog == null)
                      ? null
                      : () => _confirm(repo, catalog),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(DataRepository repo, PreventionRulesCatalog catalog) async {
    setState(() => _saving = true);
    final session = ref.read(sessionProvider);
    final me = session.user;
    // Hospital = centrado en el paciente: las tareas NO tienen dueño (las marca
    // quien esté de turno; done_by registra quién). En cuidadores/clínica se
    // asignan al cuidador del paciente si lo hay (aparecen en su agenda).
    String? assignee;
    var kind = 'staff';
    if (session.activeCenterType != CenterType.hospital) {
      final caregivers = repo.listCaregiverAssignments(patientId: widget.patientId);
      if (caregivers.isNotEmpty) {
        assignee = caregivers.first.caregiverProfileId;
        kind = 'cuidador';
      }
    }

    final specs = <ScheduledActionSpec>[];
    for (final id in _selected) {
      final cad = catalog.cadenceFor(id);
      if (cad == null) continue;
      specs.add(ScheduledActionSpec(
        ruleId: 'profesional',
        actionId: id,
        actionLabel: cad.title,
        title: cad.title,
        everyHours: cad.everyHours,
      ));
    }
    try {
      final n = await repo.generatePreventiveTasksFromSpecs(
        widget.patientId,
        specs,
        horizonHours: catalog.cadenceHorizonHours,
        organizationId: widget.organizationId,
        assigneeProfileId: assignee,
        assigneeKind: kind,
        createdBy: me?.id,
        skipNight: _skipNight,
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
