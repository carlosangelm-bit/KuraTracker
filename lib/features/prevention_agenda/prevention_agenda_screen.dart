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
  String? _patientFilter; // null = todos

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

    // Opciones de filtro por paciente (solo si hay varios y se muestra paciente).
    final patientIds = widget.showPatient
        ? (widget.tasks.map((x) => x.patientId).toSet().toList())
        : const <String>[];
    if (_patientFilter != null && !patientIds.contains(_patientFilter)) {
      _patientFilter = null;
    }

    final inRange = widget.tasks
        .where((x) =>
            !x.scheduledAt.isBefore(start) &&
            x.scheduledAt.isBefore(end) &&
            (_patientFilter == null || x.patientId == _patientFilter))
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
        if (patientIds.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(Icons.person_search_outlined, size: 18, color: t.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _patientFilter,
                    hint: const Text('Paciente: Todos'),
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Todos los pacientes')),
                      ...patientIds.map((id) => DropdownMenuItem<String?>(
                            value: id,
                            child: Text(widget.repo.getPatient(id)?.fullName ?? 'Paciente',
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) => setState(() => _patientFilter = v),
                  ),
                ),
              ],
            ),
          ),
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

    final actColor = _activityColor(task.actionId);
    return Card(
      child: ListTile(
        // Icono/color sutil por tipo de actividad (identificación rápida) +
        // un punto de estado (hecha/pendiente/vencida).
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: actColor.withOpacity(0.14),
              child: Icon(_activityIcon(task.actionId), size: 18, color: actColor),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: Icon(
                task.status == PreventiveTaskStatus.done
                    ? Icons.check_circle
                    : task.status == PreventiveTaskStatus.skipped
                        ? Icons.remove_circle
                        : Icons.circle,
                size: 12,
                color: statusColor(),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Text('$hhmm  ',
                style: TextStyle(fontWeight: FontWeight.w700, color: t.textSecondary)),
            Expanded(
              child: Text(task.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: task.status == PreventiveTaskStatus.done
                        ? TextDecoration.lineThrough
                        : null,
                  )),
            ),
          ],
        ),
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

/// Icono por tipo de actividad preventiva (identificación rápida en la agenda).
IconData _activityIcon(String? actionId) {
  switch (actionId) {
    case 'cambios_2h_registro':
    case 'cambios_2_3h':
    case 'cambios_4h':
      return Icons.airline_seat_flat_angled; // cambio postural
    case 'agho':
      return Icons.opacity; // ácidos grasos hiperoxigenados
    case 'control_humedad':
      return Icons.water_drop_outlined;
    case 'exam_piel_diario':
    case 'valoracion_piel_completa_diaria':
      return Icons.visibility_outlined; // examen/valoración de piel
    case 'aposito_preventivo':
      return Icons.healing;
    default:
      return Icons.task_alt;
  }
}

/// Color sutil por tipo de actividad (categoría), independiente del color de
/// estado (hecha/pendiente/vencida).
Color _activityColor(String? actionId) {
  switch (actionId) {
    case 'cambios_2h_registro':
    case 'cambios_2_3h':
    case 'cambios_4h':
      return const Color(0xFF2563EB); // azul
    case 'agho':
      return const Color(0xFF0D9488); // teal
    case 'control_humedad':
      return const Color(0xFF0891B2); // cian
    case 'exam_piel_diario':
    case 'valoracion_piel_completa_diaria':
      return const Color(0xFF7C3AED); // violeta
    case 'aposito_preventivo':
      return const Color(0xFF1B8A5A); // verde
    default:
      return const Color(0xFF6B6577); // gris neutro
  }
}
