import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/preventive_task.dart';
import '../../services/data_repository.dart';

/// Agenda de prevención (Fase 3): las actividades preventivas como TAREAS con
/// fecha y estado, en formato día/semana (como la agenda de citas). El personal
/// y el cuidador las marcan hechas/saltadas y ven la adherencia.
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
          return PreventiveTasksView(
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

/// Vista de tareas preventivas en formato día/semana (mismo patrón que la
/// agenda de citas): toggle de vista, navegación de fecha, agrupado por día y
/// barra de adherencia del rango visible. Reutilizada por la agenda del
/// personal y por la vista del cuidador.
class PreventiveTasksView extends StatefulWidget {
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
  State<PreventiveTasksView> createState() => _PreventiveTasksViewState();
}

enum _View { dia, semana }

class _PreventiveTasksViewState extends State<PreventiveTasksView> {
  _View _view = _View.dia;
  late DateTime _anchor; // día ancla (solo fecha)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchor = DateTime(now.year, now.month, now.day);
  }

  DateTime get _rangeStart => _view == _View.dia
      ? _anchor
      : _anchor.subtract(Duration(days: _anchor.weekday - 1)); // lunes
  DateTime get _rangeEnd =>
      _rangeStart.add(Duration(days: _view == _View.dia ? 1 : 7));

  void _shift(int units) {
    setState(() {
      _anchor = _anchor.add(Duration(days: _view == _View.dia ? units : units * 7));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final start = _rangeStart;
    final end = _rangeEnd;
    final now = DateTime.now();

    final inRange = widget.tasks
        .where((x) => !x.scheduledAt.isBefore(start) && x.scheduledAt.isBefore(end))
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    // Adherencia sobre el rango: de las ya vencidas, % hechas.
    final due = inRange.where((x) => x.scheduledAt.isBefore(now)).toList();
    final done = due.where((x) => x.status == PreventiveTaskStatus.done).length;
    final adherence = due.isEmpty ? null : (done * 100 / due.length).round();

    // Agrupar por día.
    final byDay = <String, List<PreventiveTask>>{};
    for (final task in inRange) {
      byDay.putIfAbsent(task.scheduledAt.toIso8601String().substring(0, 10), () => [])
          .add(task);
    }
    final days = byDay.keys.toList()..sort();

    return Column(
      children: [
        _controls(t, start, end),
        if (adherence != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.brandPrimary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Adherencia: $adherence%  ·  $done/${due.length} realizadas',
                style: TextStyle(fontWeight: FontWeight.w700, color: t.textPrimary)),
          ),
        Expanded(
          child: inRange.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Sin tareas en ${_view == _View.dia ? "este día" : "esta semana"}.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.textSecondary),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  children: [
                    for (final day in days) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Text(_dayLabel(day, now),
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: t.textSecondary)),
                      ),
                      ...byDay[day]!.map((task) => _TaskTile(
                            repo: widget.repo,
                            task: task,
                            byProfileId: widget.byProfileId,
                            staffId: widget.staffId,
                            onChanged: widget.onChanged,
                            showPatient: widget.showPatient,
                          )),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _controls(BrandTokens t, DateTime start, DateTime end) {
    String label;
    if (_view == _View.dia) {
      label = _dayLabel(start.toIso8601String().substring(0, 10), DateTime.now());
      if (label != 'Hoy' && label != 'Mañana' && label != 'Ayer') {
        label = start.toIso8601String().substring(0, 10);
      }
    } else {
      final endShown = end.subtract(const Duration(days: 1));
      label = '${start.toIso8601String().substring(5, 10)} – '
          '${endShown.toIso8601String().substring(5, 10)}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          SegmentedButton<_View>(
            segments: const [
              ButtonSegment(value: _View.dia, label: Text('Día')),
              ButtonSegment(value: _View.semana, label: Text('Semana')),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1),
              ),
              TextButton(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() => _anchor = DateTime(now.year, now.month, now.day));
                },
                child: const Text('Hoy'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dayLabel(String isoDay, DateTime now) {
    final today = now.toIso8601String().substring(0, 10);
    final tomorrow =
        now.add(const Duration(days: 1)).toIso8601String().substring(0, 10);
    final yesterday =
        now.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    if (isoDay == today) return 'Hoy';
    if (isoDay == tomorrow) return 'Mañana';
    if (isoDay == yesterday) return 'Ayer';
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
