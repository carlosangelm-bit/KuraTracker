import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/preventive_task.dart';
import '../../services/data_repository.dart';

/// Agenda de prevención (Fase 3): las actividades preventivas como TAREAS con
/// fecha y estado (no una simple lista). El personal del centro las ve por día,
/// las marca hechas/saltadas y consulta la adherencia. Se autogeneran desde las
/// reglas (botón "Generar plan" en la ficha de riesgo del paciente).
class PreventionAgendaScreen extends ConsumerStatefulWidget {
  const PreventionAgendaScreen({super.key});

  @override
  ConsumerState<PreventionAgendaScreen> createState() =>
      _PreventionAgendaScreenState();
}

class _PreventionAgendaScreenState
    extends ConsumerState<PreventionAgendaScreen> {
  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda de prevención'),
        actions: const [UserMenuButton()],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final orgId = user?.organizationId;
          final tasks = repo.listPreventiveTasks(organizationId: orgId);
          return _AgendaBody(
            repo: repo,
            tasks: tasks,
            byProfileId: user?.id,
            staffId: user?.staffId,
            onChanged: () => setState(() {}),
          );
        },
      ),
    );
  }
}

/// Cuerpo reutilizable: lista de tareas agrupadas por día + barra de adherencia.
/// Reutilizado por la vista del cuidador (con sus propias tareas).
class PreventiveTasksView extends StatelessWidget {
  final DataRepository repo;
  final List<PreventiveTask> tasks;
  final String? byProfileId;
  final String? staffId;
  final VoidCallback onChanged;
  final bool showPatient;

  const PreventiveTasksView({
    super.key,
    required this.repo,
    required this.tasks,
    required this.byProfileId,
    required this.staffId,
    required this.onChanged,
    this.showPatient = true,
  });

  @override
  Widget build(BuildContext context) =>
      _AgendaBody(
        repo: repo,
        tasks: tasks,
        byProfileId: byProfileId,
        staffId: staffId,
        onChanged: onChanged,
        showPatient: showPatient,
      );
}

class _AgendaBody extends StatelessWidget {
  final DataRepository repo;
  final List<PreventiveTask> tasks;
  final String? byProfileId;
  final String? staffId;
  final VoidCallback onChanged;
  final bool showPatient;

  const _AgendaBody({
    required this.repo,
    required this.tasks,
    required this.byProfileId,
    required this.staffId,
    required this.onChanged,
    this.showPatient = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    if (tasks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Sin tareas preventivas agendadas.\n'
            'Genera el plan desde la ficha de riesgo de un paciente '
            '("Generar plan preventivo").',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final now = DateTime.now();
    // Adherencia: de las tareas ya vencidas (programadas antes de ahora), % hechas.
    final due = tasks.where((x) => x.scheduledAt.isBefore(now)).toList();
    final done = due.where((x) => x.status == PreventiveTaskStatus.done).length;
    final adherence = due.isEmpty ? null : (done * 100 / due.length).round();

    // Agrupa por día (yyyy-mm-dd).
    final byDay = <String, List<PreventiveTask>>{};
    for (final task in tasks) {
      final key = task.scheduledAt.toIso8601String().substring(0, 10);
      byDay.putIfAbsent(key, () => []).add(task);
    }
    final days = byDay.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        if (adherence != null)
          Card(
            color: t.brandPrimary.withOpacity(0.06),
            child: ListTile(
              leading: Icon(Icons.insights_outlined, color: t.brandPrimary),
              title: Text('Adherencia: $adherence%',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('$done de ${due.length} tareas vencidas realizadas'),
            ),
          ),
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(_dayLabel(day, now),
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: t.textSecondary)),
          ),
          ...(byDay[day]!..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)))
              .map((task) => _TaskTile(
                    repo: repo,
                    task: task,
                    byProfileId: byProfileId,
                    staffId: staffId,
                    onChanged: onChanged,
                    showPatient: showPatient,
                  )),
        ],
      ],
    );
  }

  String _dayLabel(String isoDay, DateTime now) {
    final today = now.toIso8601String().substring(0, 10);
    final tomorrow =
        now.add(const Duration(days: 1)).toIso8601String().substring(0, 10);
    if (isoDay == today) return 'Hoy';
    if (isoDay == tomorrow) return 'Mañana';
    return isoDay;
  }
}

class _TaskTile extends StatelessWidget {
  final DataRepository repo;
  final PreventiveTask task;
  final String? byProfileId;
  final String? staffId;
  final VoidCallback onChanged;
  final bool showPatient;

  const _TaskTile({
    required this.repo,
    required this.task,
    required this.byProfileId,
    required this.staffId,
    required this.onChanged,
    required this.showPatient,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final hhmm = task.scheduledAt.toIso8601String().substring(11, 16);
    final patientName =
        showPatient ? (repo.getPatient(task.patientId)?.fullName ?? '') : '';
    final overdue = task.isPending && task.scheduledAt.isBefore(DateTime.now());

    Color statusColor() {
      switch (task.status) {
        case PreventiveTaskStatus.done:
          return t.statusSuccess;
        case PreventiveTaskStatus.skipped:
          return t.statusWarning;
        case PreventiveTaskStatus.canceled:
          return t.textDisabled;
        case PreventiveTaskStatus.pending:
          return overdue ? t.statusDanger : t.textSecondary;
      }
    }

    return Card(
      child: ListTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hhmm, style: const TextStyle(fontWeight: FontWeight.w700)),
            Icon(
              task.status == PreventiveTaskStatus.done
                  ? Icons.check_circle
                  : task.status == PreventiveTaskStatus.skipped
                      ? Icons.remove_circle_outline
                      : Icons.schedule,
              size: 16,
              color: statusColor(),
            ),
          ],
        ),
        title: Text(task.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: task.status == PreventiveTaskStatus.done
                  ? TextDecoration.lineThrough
                  : null,
            )),
        subtitle: Text([
          if (patientName.isNotEmpty) patientName,
          if (task.actionLabel != null && task.actionLabel != task.title)
            task.actionLabel!,
          if (overdue) 'Vencida',
        ].join(' · ')),
        trailing: task.isPending
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Marcar hecha',
                    icon: Icon(Icons.check, color: t.statusSuccess),
                    onPressed: () async {
                      await repo.completePreventiveTask(task,
                          byProfileId: byProfileId, staffId: staffId);
                      onChanged();
                    },
                  ),
                  IconButton(
                    tooltip: 'Saltar',
                    icon: Icon(Icons.close, color: t.textSecondary),
                    onPressed: () async {
                      await repo.skipPreventiveTask(task.id);
                      onChanged();
                    },
                  ),
                ],
              )
            : Text(task.status.label,
                style: TextStyle(color: statusColor(), fontSize: 12)),
      ),
    );
  }
}
