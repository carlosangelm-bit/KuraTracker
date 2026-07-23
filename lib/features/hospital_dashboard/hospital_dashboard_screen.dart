import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/layout/responsive.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../engine/risk/prevention_risk_engine.dart';
import '../../models/app_user.dart';
import '../../models/center_type.dart';
import '../../models/patient.dart';
import '../../models/preventive_task.dart';
import '../../services/data_repository.dart';
import '../risk/risk_board_screen.dart' show bradenBandLevel;

/// Dashboard del centro (Prevención hospitalaria). Métricas del centro activo:
/// distribución de riesgo, cumplimiento (global / por tipo / piso·área / turno),
/// vencidas, alto riesgo sin revisión, tendencia y editor de turnos. Solo lectura
/// (capa documental); la única acción es configurar los turnos del centro.
class HospitalDashboardScreen extends ConsumerStatefulWidget {
  const HospitalDashboardScreen({super.key});

  @override
  ConsumerState<HospitalDashboardScreen> createState() =>
      _HospitalDashboardScreenState();
}

class _HospitalDashboardScreenState
    extends ConsumerState<HospitalDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard del centro'),
        actions: const [UserMenuButton()],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final orgId = user?.organizationId;
          if (repo.centerTypeFor(orgId) != CenterType.hospital) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'El dashboard del centro está disponible solo en centros de '
                  'tipo Hospital.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final data = _aggregate(repo, orgId);
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text('Ventana de cumplimiento: ${data.windowLabel}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                _KpiWrap(data: data),
                const SizedBox(height: 16),
                // En desktop las tarjetas refluyen a 2-3 columnas (aprovechan el
                // ancho); en móvil quedan apiladas.
                ResponsiveColumns(
                  blockSpacing: 12,
                  blocks: [
                    _RiskDistributionCard(data: data),
                    _ComplianceByTypeCard(data: data),
                    _ComplianceByGroupCard(
                        title: 'Cumplimiento por piso', rows: data.byFloor),
                    _ComplianceByGroupCard(
                        title: 'Cumplimiento por área', rows: data.byArea),
                    if (data.byShift.isNotEmpty)
                      _ComplianceByGroupCard(
                          title: 'Cumplimiento por turno (hoy)',
                          rows: data.byShift),
                    _UnreviewedCard(patients: data.highRiskUnreviewed),
                    _TrendCard(trend: data.trend),
                    _NurseActivityCard(stats: data.nurseActivity),
                    if (user?.role == AppRole.admin ||
                        user?.role == AppRole.master)
                      _ShiftEditorCard(
                        repo: repo,
                        orgId: orgId,
                        shifts: data.shifts,
                        onSaved: () => setState(() {}),
                      ),
                    const _LppPlaceholderCard(),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  _DashData _aggregate(DataRepository repo, String? orgId) {
    final now = DateTime.now();
    final shifts = repo.shiftConfigFor(orgId);
    final windowStart = repo.complianceWindowStart(orgId, now);

    // Población: pacientes del centro con internamiento activo (encamados).
    final patients = repo
        .listAllPatients()
        .where((p) => p.organizationId == orgId && repo.activeAdmission(p.id) != null)
        .toList();

    var alto = 0, medio = 0, bajo = 0, sinVal = 0;
    var doneTotal = 0, expectedTotal = 0, overdue = 0;
    final byType = <String, List<int>>{}; // title -> [done, expected]
    final byFloor = <String, List<int>>{};
    final byArea = <String, List<int>>{};
    final highRiskUnreviewed = <Patient>[];

    for (final p in patients) {
      final adm = repo.activeAdmission(p.id);
      final last = repo.latestRiskAssessment(p.id);
      final braden = last?.bradenScore;
      final band = bradenBandLevel(braden);
      switch (band) {
        case RiskLevel.alto:
          alto++;
        case RiskLevel.medio:
          medio++;
        case RiskLevel.bajo:
          bajo++;
        default:
          sinVal++;
      }
      // Alto riesgo sin revisión dentro de la ventana actual.
      if (band == RiskLevel.alto &&
          (last == null || last.assessedAt.isBefore(windowStart))) {
        highRiskUnreviewed.add(p);
      }

      final comp = repo.preventiveCompliance(p.id, organizationId: orgId, now: now);
      doneTotal += comp.doneTotal;
      expectedTotal += comp.expectedTotal;
      final floor = adm?.floor ?? '—';
      final area = adm?.area ?? '—';
      final f = byFloor.putIfAbsent(floor, () => [0, 0]);
      f[0] += comp.doneTotal;
      f[1] += comp.expectedTotal;
      final a = byArea.putIfAbsent(area, () => [0, 0]);
      a[0] += comp.doneTotal;
      a[1] += comp.expectedTotal;
      for (final t in comp.byType) {
        final e = byType.putIfAbsent(t.title, () => [0, 0]);
        e[0] += t.done;
        e[1] += t.expected;
      }

      // Vencidas activas: tareas pendientes con hora pasada.
      overdue += repo
          .listPreventiveTasks(patientId: p.id)
          .where((t) => t.isPending && t.scheduledAt.isBefore(now))
          .length;
    }

    // Cumplimiento por turno (hoy): reparte las tareas del día por hora.
    final byShift = <_GroupRow>[];
    if (shifts.isNotEmpty) {
      final todayStart = DateTime(now.year, now.month, now.day);
      final tasksToday = repo
          .listPreventiveTasks(organizationId: orgId)
          .where((t) =>
              t.status != PreventiveTaskStatus.canceled &&
              !t.scheduledAt.isBefore(todayStart) &&
              t.scheduledAt.isBefore(todayStart.add(const Duration(days: 1))))
          .toList();
      for (final s in shifts) {
        final start = s['startHour'] as int;
        final end = s['endHour'] as int;
        bool inShift(int h) =>
            start <= end ? (h >= start && h < end) : (h >= start || h < end);
        final inS = tasksToday.where((t) => inShift(t.scheduledAt.hour));
        final done = inS.where((t) => t.status == PreventiveTaskStatus.done).length;
        final exp = inS.length;
        byShift.add(_GroupRow('${s['name']}', done, exp));
      }
    }

    // Tendencia: cumplimiento diario de los últimos 7 días (tareas del centro
    // programadas ese día, hechas / total no canceladas).
    final allTasks = repo
        .listPreventiveTasks(organizationId: orgId)
        .where((t) => t.status != PreventiveTaskStatus.canceled)
        .toList();
    final trend = <_TrendDay>[];
    for (var i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final next = day.add(const Duration(days: 1));
      final dayTasks = allTasks.where(
          (t) => !t.scheduledAt.isBefore(day) && t.scheduledAt.isBefore(next));
      final exp = dayTasks.length;
      final done = dayTasks.where((t) => t.status == PreventiveTaskStatus.done).length;
      trend.add(_TrendDay(day, done, exp));
    }

    String windowLabel;
    if (shifts.isEmpty) {
      windowLabel = 'últimas 24 h';
    } else {
      final cur = shifts.firstWhere(
        (s) {
          final start = s['startHour'] as int;
          final end = s['endHour'] as int;
          final h = now.hour;
          return start <= end ? (h >= start && h < end) : (h >= start || h < end);
        },
        orElse: () => shifts.first,
      );
      windowLabel =
          'turno ${cur['name']} (${cur['startHour']}:00–${cur['endHour']}:00)';
    }

    List<_GroupRow> toRows(Map<String, List<int>> m) {
      final rows = m.entries
          .map((e) => _GroupRow(e.key, e.value[0], e.value[1]))
          .where((r) => r.expected > 0)
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      return rows;
    }

    final typeRows = byType.entries
        .map((e) => _GroupRow(e.key, e.value[0], e.value[1]))
        .where((r) => r.expected > 0)
        .toList()
      ..sort((a, b) => a.pct.compareTo(b.pct)); // peor cumplimiento arriba

    // Actividad de enfermería (últimos 7 días): tareas resueltas (hechas /
    // saltadas) por profesional que las marcó (done_by).
    final weekStart =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final nameById = <String, String>{
      for (final s in repo.listStaff(organizationId: orgId))
        if (s.profileId != null) s.profileId!: s.fullName,
      for (final u in repo.listUsers()) u.id: u.fullName,
    };
    final byNurse = <String, List<int>>{}; // profileId -> [hechas, saltadas]
    for (final t in allTasks) {
      final by = t.doneBy;
      final at = t.doneAt;
      if (by == null || at == null || at.isBefore(weekStart)) continue;
      final e = byNurse.putIfAbsent(by, () => [0, 0]);
      if (t.status == PreventiveTaskStatus.done) {
        e[0]++;
      } else if (t.status == PreventiveTaskStatus.skipped) {
        e[1]++;
      }
    }
    final nurseActivity = byNurse.entries
        .map((e) => _NurseStat(
            name: nameById[e.key] ?? 'Personal',
            done: e.value[0],
            skipped: e.value[1]))
        .where((n) => n.done + n.skipped > 0)
        .toList()
      ..sort((a, b) => b.done.compareTo(a.done));

    return _DashData(
      totalAdmitted: patients.length,
      alto: alto,
      medio: medio,
      bajo: bajo,
      sinValoracion: sinVal,
      overdue: overdue,
      globalDone: doneTotal,
      globalExpected: expectedTotal,
      byType: typeRows,
      byFloor: toRows(byFloor),
      byArea: toRows(byArea),
      byShift: byShift,
      highRiskUnreviewed: highRiskUnreviewed,
      trend: trend,
      nurseActivity: nurseActivity,
      shifts: shifts,
      windowLabel: windowLabel,
    );
  }
}

// ---------------------------------------------------------------------------
// Modelos de agregación (locales al dashboard).
// ---------------------------------------------------------------------------

class _GroupRow {
  final String label;
  final int done;
  final int expected;
  const _GroupRow(this.label, this.done, this.expected);
  int get pct => expected == 0 ? 0 : (done * 100 / expected).round();
}

class _TrendDay {
  final DateTime day;
  final int done;
  final int expected;
  const _TrendDay(this.day, this.done, this.expected);
  int get pct => expected == 0 ? 0 : (done * 100 / expected).round();
}

/// Actividad de un miembro del personal (enfermería) en la ventana: tareas
/// preventivas hechas y saltadas por esa persona.
class _NurseStat {
  final String name;
  final int done;
  final int skipped;
  const _NurseStat({required this.name, required this.done, required this.skipped});
}

class _DashData {
  final int totalAdmitted;
  final int alto, medio, bajo, sinValoracion;
  final int overdue;
  final int globalDone, globalExpected;
  final List<_GroupRow> byType;
  final List<_GroupRow> byFloor;
  final List<_GroupRow> byArea;
  final List<_GroupRow> byShift;
  final List<Patient> highRiskUnreviewed;
  final List<_TrendDay> trend;
  final List<_NurseStat> nurseActivity;
  final List<Map<String, dynamic>> shifts;
  final String windowLabel;
  const _DashData({
    required this.totalAdmitted,
    required this.alto,
    required this.medio,
    required this.bajo,
    required this.sinValoracion,
    required this.overdue,
    required this.globalDone,
    required this.globalExpected,
    required this.byType,
    required this.byFloor,
    required this.byArea,
    required this.byShift,
    required this.highRiskUnreviewed,
    required this.trend,
    required this.nurseActivity,
    required this.shifts,
    required this.windowLabel,
  });
  int get globalPct =>
      globalExpected == 0 ? 0 : (globalDone * 100 / globalExpected).round();
}

Color _pctColor(int p) => p >= 85
    ? KuraColors.success
    : p >= 60
        ? KuraColors.warning
        : KuraColors.danger;

// ---------------------------------------------------------------------------
// Widgets de presentación.
// ---------------------------------------------------------------------------

class _KpiWrap extends StatelessWidget {
  final _DashData data;
  const _KpiWrap({required this.data});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _KpiCard(
            label: 'Encamados', value: '${data.totalAdmitted}', color: KuraColors.primary),
        _KpiCard(label: 'Alto riesgo', value: '${data.alto}', color: KuraColors.danger),
        _KpiCard(
            label: 'Sin valoración',
            value: '${data.sinValoracion}',
            color: KuraColors.darkText),
        _KpiCard(label: 'Vencidas', value: '${data.overdue}', color: KuraColors.warning),
        _KpiCard(
            label: 'Cumplimiento',
            value: data.globalExpected == 0 ? '—' : '${data.globalPct}%',
            color: _pctColor(data.globalPct)),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _KpiCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _RiskDistributionCard extends StatelessWidget {
  final _DashData data;
  const _RiskDistributionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final segs = <(String, int, Color)>[
      ('Alto', data.alto, KuraColors.danger),
      ('Medio', data.medio, KuraColors.warning),
      ('Bajo', data.bajo, KuraColors.success),
      ('Sin valoración', data.sinValoracion, KuraColors.darkText),
    ];
    final total = data.totalAdmitted;
    return _SectionCard(
      title: 'Distribución de riesgo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [
                  for (final s in segs)
                    if (s.$2 > 0)
                      Expanded(
                        flex: s.$2,
                        child: Container(height: 12, color: s.$3),
                      ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final s in segs)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: s.$3, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${s.$1}: ${s.$2}',
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fila con etiqueta + done/expected + % + barra de progreso coloreada.
class _BarRow extends StatelessWidget {
  final String label;
  final int done;
  final int expected;
  const _BarRow(
      {required this.label, required this.done, required this.expected});

  @override
  Widget build(BuildContext context) {
    final pct = expected == 0 ? 0 : (done * 100 / expected).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis)),
              Text('$done/$expected · $pct%',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _pctColor(pct))),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: expected == 0 ? 0 : done / expected,
              minHeight: 6,
              backgroundColor: KuraColors.chipBg,
              color: _pctColor(pct),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComplianceByTypeCard extends StatelessWidget {
  final _DashData data;
  const _ComplianceByTypeCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Cumplimiento por tipo de actividad',
      child: data.byType.isEmpty
          ? const Text('Sin actividades esperadas en la ventana actual.',
              style: TextStyle(fontSize: 13))
          : Column(
              children: [
                for (final r in data.byType)
                  _BarRow(label: r.label, done: r.done, expected: r.expected),
              ],
            ),
    );
  }
}

class _ComplianceByGroupCard extends StatelessWidget {
  final String title;
  final List<_GroupRow> rows;
  const _ComplianceByGroupCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      child: rows.isEmpty
          ? const Text('Sin datos.', style: TextStyle(fontSize: 13))
          : Column(
              children: [
                for (final r in rows)
                  _BarRow(label: r.label, done: r.done, expected: r.expected),
              ],
            ),
    );
  }
}

class _UnreviewedCard extends StatelessWidget {
  final List<Patient> patients;
  const _UnreviewedCard({required this.patients});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Alto riesgo sin revisión en la ventana',
      child: patients.isEmpty
          ? const Text('Todos los pacientes de alto riesgo tienen valoración '
              'dentro de la ventana.', style: TextStyle(fontSize: 13))
          : Column(
              children: [
                for (final p in patients)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.priority_high,
                        color: KuraColors.danger),
                    title: Text(p.fullName, style: const TextStyle(fontSize: 14)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/patients/${p.id}/risk'),
                  ),
              ],
            ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<_TrendDay> trend;
  const _TrendCard({required this.trend});

  @override
  Widget build(BuildContext context) {
    // Abreviatura del día en español (evita depender de datos de locale 'es').
    const dias = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];
    String dayLabel(DateTime d) => dias[d.weekday - 1];
    final hasData = trend.any((d) => d.expected > 0);
    return _SectionCard(
      title: 'Tendencia de cumplimiento (7 días)',
      child: !hasData
          ? const Text('Sin actividades programadas en el periodo.',
              style: TextStyle(fontSize: 13))
          : SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in trend)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(d.expected == 0 ? '—' : '${d.pct}%',
                              style: const TextStyle(fontSize: 10)),
                          const SizedBox(height: 2),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            height: d.expected == 0
                                ? 2
                                : (6 + d.pct * 0.7),
                            decoration: BoxDecoration(
                              color: d.expected == 0
                                  ? KuraColors.chipBg
                                  : _pctColor(d.pct),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(dayLabel(d.day),
                              style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Actividad de enfermería (últimos 7 días): tareas de ronda hechas/saltadas
/// por profesional, para que el admin vea la ejecución del personal.
class _NurseActivityCard extends StatelessWidget {
  final List<_NurseStat> stats;
  const _NurseActivityCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final maxDone = stats.fold<int>(1, (m, s) => s.done > m ? s.done : m);
    return _SectionCard(
      title: 'Actividad de enfermería (7 días)',
      child: stats.isEmpty
          ? const Text('Sin actividad de rondas registrada en el periodo.',
              style: TextStyle(fontSize: 13))
          : Column(
              children: [
                for (final s in stats)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: KuraColors.primary.withValues(alpha: 0.12),
                          child: Text(
                            s.name.isNotEmpty ? s.name[0] : '?',
                            style: const TextStyle(
                                color: KuraColors.primary,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (s.done / maxDone).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: KuraColors.chipBg,
                                  color: KuraColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${s.done} hechas',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                            if (s.skipped > 0)
                              Text('${s.skipped} saltadas',
                                  style: const TextStyle(
                                      fontSize: 11, color: KuraColors.warning)),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _LppPlaceholderCard extends StatelessWidget {
  const _LppPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Incidencia / prevalencia de LPP',
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, size: 18, color: KuraColors.darkText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Pendiente de definición clínica (numerador / denominador / '
              'ventana) con el equipo médico.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Editor de turnos del centro (admin/master). Escribe organizations.shift_config
/// vía repo.setShiftConfig; sin turnos = ventana de 24 h.
class _ShiftEditorCard extends StatelessWidget {
  final DataRepository repo;
  final String? orgId;
  final List<Map<String, dynamic>> shifts;
  final VoidCallback onSaved;
  const _ShiftEditorCard({
    required this.repo,
    required this.orgId,
    required this.shifts,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Turnos del centro',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shifts.isEmpty)
            const Text(
                'Sin turnos configurados — la ventana de cumplimiento usa las '
                'últimas 24 h.',
                style: TextStyle(fontSize: 13))
          else
            for (final s in shifts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                    '• ${s['name']}: ${s['startHour']}:00 – ${s['endHour']}:00',
                    style: const TextStyle(fontSize: 13)),
              ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.schedule, size: 18),
              label: const Text('Configurar turnos'),
              onPressed: () => _editShifts(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editShifts(BuildContext context) async {
    final working = shifts
        .map((s) => {
              'name': '${s['name']}',
              'startHour': s['startHour'] as int,
              'endHour': s['endHour'] as int,
            })
        .toList();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 4,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Turnos del centro',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                      'Definen la ventana de cumplimiento. Sin turnos = 24 h. '
                      'Un turno que termina antes de empezar cruza medianoche.',
                      style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var i = 0; i < working.length; i++)
                            _ShiftEditRow(
                              shift: working[i],
                              onChanged: () => setSheet(() {}),
                              onRemove: () =>
                                  setSheet(() => working.removeAt(i)),
                            ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Añadir turno'),
                              onPressed: () => setSheet(() => working.add({
                                    'name': 'Turno ${working.length + 1}',
                                    'startHour': 7,
                                    'endHour': 15,
                                  })),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            working.clear();
                            Navigator.of(ctx).pop(true);
                          },
                          child: const Text('Usar 24 h'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Guardar'),
                        ),
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

    if (saved != true || orgId == null) return;
    try {
      await repo.setShiftConfig(orgId!, working);
      onSaved();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turnos actualizados')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    }
  }
}

class _ShiftEditRow extends StatelessWidget {
  final Map<String, dynamic> shift;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  const _ShiftEditRow(
      {required this.shift, required this.onChanged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: '${shift['name']}',
              decoration: const InputDecoration(
                  labelText: 'Nombre', isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => shift['name'] = v,
            ),
          ),
          const SizedBox(width: 8),
          _HourDropdown(
            label: 'Inicio',
            value: shift['startHour'] as int,
            onChanged: (v) {
              shift['startHour'] = v;
              onChanged();
            },
          ),
          const SizedBox(width: 8),
          _HourDropdown(
            label: 'Fin',
            value: shift['endHour'] as int,
            onChanged: (v) {
              shift['endHour'] = v;
              onChanged();
            },
          ),
          IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _HourDropdown extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _HourDropdown(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: DropdownButtonFormField<int>(
        value: value,
        isDense: true,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
        items: [
          for (var h = 0; h < 24; h++)
            DropdownMenuItem(value: h, child: Text('$h:00')),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
