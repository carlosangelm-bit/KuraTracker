import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/layout/responsive.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show kFloatingNavBarHeight, UserMenuButton;
import '../../core/widgets/kura_glass_card.dart';
import '../../core/widgets/kura_primary_fab.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../engine/sheehan_decision_style.dart';
import '../../models/app_user.dart';
import '../../models/center_type.dart';
import '../../models/patient.dart';
import '../../models/patient_admission.dart';
import '../../services/data_repository.dart';
import '../risk/risk_board_screen.dart' show bradenBandLevel;
import '../risk/risk_theme.dart';
import '../patients/patient_list_tile.dart';
import '../patients/patient_progress_status.dart';
import '../patients/patient_wound_summary.dart';
import '../patients/patients_view_preferences.dart';
import '../patients/wound_picker_sheet.dart';

/// Pantalla de inicio como TABLERO DE TRIAGE: en vez de un resumen plano,
/// prioriza lo que necesita atencion (semaforo de trayectoria de Sheehan)
/// y ofrece las mismas acciones rapidas (Valoracion/Seguimiento) que la
/// lista de pacientes, para actuar sin dar rodeos.
///
/// No inventa datos: todo lo "pendiente" se deriva del semaforo de avance
/// ([PatientProgressStatus], checkpoint de Sheehan), NO de una cadencia o
/// calendario (que el modelo no tiene). Reutiliza los mismos componentes
/// que [PatientsListScreen] (tile, estatus, resumen, selector de herida,
/// preferencias de filtro) para no duplicar logica ni estilo.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

/// Ventana temporal para los indicadores de actividad del admin. El resto de
/// datos (estatus, etiologías, KPIs) se analizan siempre en tiempo real.
enum _Period { mes, d30, d14, d7 }

extension _PeriodX on _Period {
  String get label => switch (this) {
        _Period.mes => 'Mes actual',
        _Period.d30 => '30 días',
        _Period.d14 => '14 días',
        _Period.d7 => '7 días',
      };

  DateTime cutoff(DateTime now) => switch (this) {
        _Period.mes => DateTime(now.year, now.month, 1),
        _Period.d30 => now.subtract(const Duration(days: 30)),
        _Period.d14 => now.subtract(const Duration(days: 14)),
        _Period.d7 => now.subtract(const Duration(days: 7)),
      };
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  // Cuantos pacientes "recientes" (no urgentes) se muestran antes de
  // ofrecer "Ver todos": el tablero debe leerse en segundos, no ser la
  // lista completa (esa vive en /patients).
  static const int _recentLimit = 6;

  // Filtro de temporalidad (solo para los indicadores de actividad del admin:
  // "por sitio" y "carga por Kurador"). Por defecto, el mes actual.
  _Period _sitePeriod = _Period.mes;
  _Period _kuradorPeriod = _Period.mes;

  // Accion rapida "Valoracion": misma ruta y query que PatientsListScreen.
  void _goToValoracion(String patientId) {
    context.go('/patients/$patientId/consultation/new?visitType=valoracion');
  }

  // Accion rapida "Seguimiento": misma resolucion que PatientsListScreen
  // (directo si hay 1 herida activa, selector si hay varias, nada si no
  // hay heridas activas).
  Future<void> _goToSeguimiento(DataRepository repo, String patientId) async {
    final summary = PatientWoundSummary.compute(repo, patientId);
    if (!summary.hasActiveWounds) return;
    if (summary.activeCount == 1) {
      context.go('/patients/$patientId/wound/${summary.activeWounds.first.id}/follow-up');
      return;
    }
    final chosen = await showWoundPickerSheet(context, summary.activeWounds);
    if (chosen != null && mounted) {
      context.go('/patients/$patientId/wound/${chosen.id}/follow-up');
    }
  }

  // Abre la lista de pacientes ya filtrada por un estatus del semaforo,
  // reutilizando las preferencias persistidas que consume
  // PatientsListScreen (conserva la vista y el filtro de sitio del usuario;
  // solo cambia el filtro de trayectoria). `null` limpia ese filtro.
  Future<void> _openPatients({ProgressStatus? status}) async {
    final current = await PatientsViewPreferencesStore.load();
    await PatientsViewPreferencesStore.save(
      current.copyWith(progressStatuses: status == null ? const {} : {status}),
    );
    if (mounted) context.go('/patients');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = session.user;
    final tokens = BrandTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.background,
      // Fondo con color (degradado + blobs) para que el vidrio de las
      // tarjetas tenga algo que refractar detras.
      body: Stack(
        children: [
          const Positioned.fill(child: _DashboardBackground()),
          Positioned.fill(
            child: repoAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (repo) {
                // Centro tipo HOSPITAL: el Inicio es una home de PREVENCIÓN
                // (centrada en el paciente), no el tablero de tratamiento. Todo
                // el personal activo ve a los pacientes del centro.
                if (repo.centerTypeFor(user?.organizationId) ==
                    CenterType.hospital) {
                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      20 + MediaQuery.of(context).viewPadding.top,
                      16,
                      MediaQuery.of(context).viewPadding.bottom +
                          kFloatingNavBarHeight +
                          32,
                    ),
                    children: _hospitalChildren(context, repo, user),
                  );
                }
                // Aislamiento por rol: clínico ve SUS pacientes; admin los del
                // centro. El master no llega aquí (va a /platform).
                final isAdmin = user?.role == AppRole.admin;
                final patients = isAdmin
                    ? repo.listAllPatients()
                    : (user?.staffId != null
                        ? repo.listPatientsForStaff(user!.staffId!)
                        : <Patient>[]);
                // Un solo cómputo del semáforo por paciente.
                final triage = patients.map((p) {
                  final summary = PatientWoundSummary.compute(repo, p.id);
                  final progress =
                      PatientProgressStatus.compute(repo, summary.activeWounds);
                  return _Triage(patient: p, summary: summary, progress: progress);
                }).toList();
                return ListView(
                  // Espacio inferior para que el último elemento no quede tapado
                  // por la barra de navegación flotante.
                  padding: EdgeInsets.fromLTRB(
                    16,
                    // El shell ya no pone AppBar; se compensa el inset superior
                    // (barra de estado/notch) para que el encabezado no quede
                    // debajo de él.
                    20 + MediaQuery.of(context).viewPadding.top,
                    16,
                    MediaQuery.of(context).viewPadding.bottom +
                        kFloatingNavBarHeight +
                        32,
                  ),
                  // Dos layouts distintos según el rol (mismos tokens/componentes).
                  children: isAdmin
                      ? _adminChildren(context, repo, user, patients, triage)
                      : _clinicianChildren(context, repo, user, triage),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: KuraPrimaryFab(
        onPressed: () => context.go('/patients/new'),
        icon: Icons.person_add,
        label: 'Nuevo paciente',
      ),
    );
  }

  // Tile reutilizado (mismo componente y acciones que PatientsListScreen),
  // con superficie "glass-lite": KuraGlassCard SIN BackdropFilter, para que
  // el scroll de la lista no cargue un blur real por fila (fluidez).
  Widget _tile(DataRepository repo, _Triage t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PatientListTile(
        patient: t.patient,
        summary: t.summary,
        progressStatus: t.progress,
        onTap: () => context.push('/patients/${t.patient.id}'),
        onValoracion: () => _goToValoracion(t.patient.id),
        onSeguimiento: () => _goToSeguimiento(repo, t.patient.id),
        surfaceBuilder: (child) => KuraGlassCard(
          blur: false,
          borderRadius: 18,
          padding: EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }

  // Prioridad "peor primero": rojo > amarillo (dentro de la seccion de
  // atencion).
  static int _severityRank(ProgressStatus s) {
    switch (s) {
      case ProgressStatus.danger:
        return 0;
      case ProgressStatus.warning:
        return 1;
      case ProgressStatus.good:
        return 2;
      case ProgressStatus.noData:
        return 3;
    }
  }

  List<Widget> _greeting(BuildContext context, AppUser? user, String subtitle) {
    final t = BrandTokens.of(context);
    return [
      // Encabezado: saludo a la izquierda y el avatar/menú de usuario a la
      // derecha (antes vivía en el AppBar del shell, ya removido).
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, ${user?.fullName.split(' ').first ?? ''} 👋',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: t.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: UserMenuButton(),
          ),
        ],
      ),
    ];
  }

  /// Última actividad del paciente = consulta más reciente (por fecha de
  /// visita). No hay cadencia/calendario; esto solo ordena "recientes".
  DateTime _lastActivity(DataRepository repo, String patientId) {
    final consultas = repo.listConsultationsForPatient(patientId);
    if (consultas.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return consultas
        .map((c) => c.visitDate)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Serie de área (cm²) de la primera herida activa, para el sparkline.
  /// Vacía si no hay al menos 2 mediciones (no se puede trazar tendencia).
  List<double> _areaSeries(DataRepository repo, _Triage t) {
    if (t.summary.activeWounds.isEmpty) return const [];
    final ms = repo.listMeasurementsForWound(t.summary.activeWounds.first.id);
    if (ms.length < 2) return const [];
    return ms.map((m) => m.areaCm2).toList();
  }

  // ---- Layout CLÍNICO (operativo, sus pacientes) ----
  List<Widget> _clinicianChildren(
      BuildContext context, DataRepository repo, AppUser? user, List<_Triage> triage) {
    final t = BrandTokens.of(context);
    final activePatients = triage.where((x) => x.patient.isActive).length;
    final activeWounds = triage.fold<int>(0, (n, x) => n + x.summary.activeCount);
    final dangerCount = triage.where((x) => x.worst == ProgressStatus.danger).length;
    // Resumen del panel del clínico (mismos gráficos reutilizados del admin,
    // pero sobre SUS pacientes): distribución de estatus + mezcla de casos.
    final green = triage.where((x) => x.worst == ProgressStatus.good).length;
    final amber = triage.where((x) => x.worst == ProgressStatus.warning).length;
    final noData = triage.where((x) => x.worst == ProgressStatus.noData).length;
    final etiologyCounts = <Etiologia, int>{};
    for (final x in triage) {
      for (final w in x.summary.activeWounds) {
        etiologyCounts[w.etiology] = (etiologyCounts[w.etiology] ?? 0) + 1;
      }
    }
    final etiologies = etiologyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final attention = triage
        .where((x) =>
            x.worst == ProgressStatus.danger || x.worst == ProgressStatus.warning)
        .toList()
      ..sort((a, b) => _severityRank(a.worst).compareTo(_severityRank(b.worst)));
    final recent = [...triage]
      ..sort((a, b) => _lastActivity(repo, b.patient.id)
          .compareTo(_lastActivity(repo, a.patient.id)));

    return [
      ..._greeting(context, user, 'Tu tablero de hoy · lo que necesita atención va primero'),
      const SizedBox(height: 20),
      _HeroCard(
        activePatients: activePatients,
        activeWounds: activeWounds,
        dangerCount: dangerCount,
        onTapAttention: () => _openPatients(status: ProgressStatus.danger),
      ),
      const SizedBox(height: 16),
      _QuickAccessBar(
        onSearch: () => _openPatients(),
        onReports: () => context.go('/reports'),
      ),
      const SizedBox(height: 28),
      if (triage.isEmpty)
        const _EmptyDashboard(isAdmin: false)
      else ...[
        // Resumen de mi panel: donut de estatus + tipos de lesión (en
        // escritorio lado a lado; en móvil apilados).
        ResponsiveColumns(
          blocks: [
            _sectionBlock(
              context,
              icon: Icons.donut_small_outlined,
              title: 'Estado de mis pacientes',
              count: triage.length,
              child: _StatusDonut(
                  green: green, amber: amber, red: dangerCount, noData: noData),
            ),
            if (etiologies.isNotEmpty)
              _sectionBlock(
                context,
                icon: Icons.category_outlined,
                title: 'Tipos de lesión',
                count: etiologies.length,
                child: _CategoryBars(
                  entries: [
                    for (final e in etiologies) _BarDatum(label: e.key.label, value: e.value)
                  ],
                  color: t.brandPrimary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        _SectionHeader(
          icon: Icons.priority_high_rounded,
          title: 'Requieren atención',
          count: attention.length,
          color: dangerCount > 0 ? t.statusDanger : t.statusWarning,
        ),
        const SizedBox(height: 12),
        if (attention.isEmpty)
          const _AttentionEmpty()
        else
          ...attention.map((x) => _tile(repo, x)),
        const SizedBox(height: 28),
        _SectionHeader(
          icon: Icons.history,
          title: 'Continuar donde te quedaste',
          count: recent.length,
          color: t.info,
        ),
        const SizedBox(height: 12),
        ...recent.take(_recentLimit).map((x) => _RecentPatientTile(
              triage: x,
              series: _areaSeries(repo, x),
              onTap: () => context.push('/patients/${x.patient.id}'),
            )),
        if (recent.length > _recentLimit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openPatients(),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text('Ver todos los pacientes (${recent.length})'),
            ),
          ),
      ],
    ];
  }

  // ---- Layout HOSPITAL (Inicio de prevención, centrado en el paciente) ----
  // Métricas del flujo hospitalario: encamados, distribución por banda de
  // Braden, cumplimiento de rondas y lo que requiere atención. El análisis
  // completo (por turno/piso/área, tendencia, turnos) vive en /hospital.
  List<Widget> _hospitalChildren(
      BuildContext context, DataRepository repo, AppUser? user) {
    final t = BrandTokens.of(context);
    final orgId = user?.organizationId;
    final now = DateTime.now();
    final windowStart = repo.complianceWindowStart(orgId, now);

    // Población: pacientes del centro con internamiento activo (encamados).
    final patients = repo
        .listAllPatients()
        .where((p) =>
            p.organizationId == orgId && repo.activeAdmission(p.id) != null)
        .toList();

    var alto = 0, medio = 0, bajo = 0, sinVal = 0;
    var overdueTotal = 0, doneTotal = 0, expectedTotal = 0;
    final attention = <_HospEntry>[];
    for (final p in patients) {
      final last = repo.latestRiskAssessment(p.id);
      final band = bradenBandLevel(last?.bradenScore);
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
      final comp =
          repo.preventiveCompliance(p.id, organizationId: orgId, now: now);
      doneTotal += comp.doneTotal;
      expectedTotal += comp.expectedTotal;
      final pOverdue = repo
          .listPreventiveTasks(patientId: p.id)
          .where((x) => x.isPending && x.scheduledAt.isBefore(now))
          .length;
      overdueTotal += pOverdue;
      // Alto riesgo sin valoración dentro de la ventana de cumplimiento.
      final unreviewed = band == RiskLevel.alto &&
          (last == null || last.assessedAt.isBefore(windowStart));
      if (band == RiskLevel.alto || pOverdue > 0 || unreviewed) {
        attention.add(_HospEntry(
          patient: p,
          band: band,
          admission: repo.activeAdmission(p.id),
          overdue: pOverdue,
          unreviewed: unreviewed,
        ));
      }
    }
    final globalPct =
        expectedTotal == 0 ? 0 : (doneTotal * 100 / expectedTotal).round();
    final compColor = expectedTotal == 0
        ? t.textSecondary
        : globalPct >= 85
            ? t.statusSuccess
            : globalPct >= 60
                ? t.statusWarning
                : t.statusDanger;

    int bandRank(RiskLevel? l) => switch (l) {
          RiskLevel.alto => 0,
          RiskLevel.medio => 1,
          RiskLevel.bajo => 2,
          _ => 3,
        };
    // Prioridad: sin revisar → más vencidas → peor banda → nombre.
    attention.sort((a, b) {
      if (a.unreviewed != b.unreviewed) return a.unreviewed ? -1 : 1;
      if (a.overdue != b.overdue) return b.overdue.compareTo(a.overdue);
      final r = bandRank(a.band).compareTo(bandRank(b.band));
      if (r != 0) return r;
      return a.patient.fullName.compareTo(b.patient.fullName);
    });

    return [
      ..._greeting(context, user,
          'Prevención hospitalaria · lo que requiere atención va primero'),
      const SizedBox(height: 20),
      _KpiRow(kpis: [
        _Kpi(
            icon: Icons.local_hotel_outlined,
            label: 'Encamados',
            value: '${patients.length}',
            color: t.info),
        _Kpi(
            icon: Icons.priority_high_rounded,
            label: 'Alto riesgo',
            value: '$alto',
            color: t.statusDanger),
        _Kpi(
            icon: Icons.schedule_outlined,
            label: 'Rondas vencidas',
            value: '$overdueTotal',
            color: t.statusWarning),
        _Kpi(
            icon: Icons.verified_outlined,
            label: 'Cumplimiento',
            value: expectedTotal == 0 ? '—' : '$globalPct%',
            color: compColor),
      ]),
      const SizedBox(height: 16),
      _HospitalQuickAccess(
        onRondas: () => context.go('/prevention-agenda'),
        onTablero: () => context.go('/risk'),
        onDashboard: () => context.go('/hospital'),
      ),
      const SizedBox(height: 28),
      if (patients.isEmpty)
        const _HospitalEmpty()
      else ...[
        _sectionBlock(
          context,
          icon: Icons.donut_small_outlined,
          title: 'Distribución de riesgo (Braden)',
          count: patients.length,
          child: _RiskBandsBar(
            alto: alto,
            medio: medio,
            bajo: bajo,
            sinValoracion: sinVal,
          ),
        ),
        const SizedBox(height: 28),
        _SectionHeader(
          icon: Icons.priority_high_rounded,
          title: 'Requieren atención',
          count: attention.length,
          color: attention.any((e) => e.unreviewed || e.band == RiskLevel.alto)
              ? t.statusDanger
              : t.statusWarning,
        ),
        const SizedBox(height: 12),
        if (attention.isEmpty)
          const _AttentionEmpty()
        else
          // En desktop las tarjetas de atención se reparten en 2-3 columnas
          // (aprovechan el ancho); en móvil quedan apiladas.
          ResponsiveColumns(
            blockSpacing: 10,
            blocks: [
              for (final e in attention)
                _HospitalAttentionTile(
                  entry: e,
                  onTap: () => context.push('/patients/${e.patient.id}/risk'),
                ),
            ],
          ),
      ],
    ];
  }

  // ---- Layout ADMIN (supervisión del centro) ----
  List<Widget> _adminChildren(BuildContext context, DataRepository repo,
      AppUser? user, List<Patient> patients, List<_Triage> triage) {
    final t = BrandTokens.of(context);
    final activePatients = patients.where((p) => p.isActive).length;
    final activeWounds = triage.fold<int>(0, (n, x) => n + x.summary.activeCount);
    final green = triage.where((x) => x.worst == ProgressStatus.good).length;
    final amber = triage.where((x) => x.worst == ProgressStatus.warning).length;
    final red = triage.where((x) => x.worst == ProgressStatus.danger).length;
    final noData = triage.where((x) => x.worst == ProgressStatus.noData).length;
    final closureRate =
        triage.isEmpty ? 0 : ((green / triage.length) * 100).round();

    // Tipos de lesión (etiología) — tiempo real, sobre heridas activas.
    final etiologyCounts = <Etiologia, int>{};
    for (final x in triage) {
      for (final w in x.summary.activeWounds) {
        etiologyCounts[w.etiology] = (etiologyCounts[w.etiology] ?? 0) + 1;
      }
    }
    final etiologies = etiologyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Todas las consultas del centro (base de los indicadores por periodo).
    final now = DateTime.now();
    final allConsultations = [
      for (final p in patients) ...repo.listConsultationsForPatient(p.id)
    ];

    // Pacientes y sesiones por sitio, filtrado por _sitePeriod: sesiones =
    // consultas en el periodo; pacientes = distintos atendidos en el periodo.
    final sites = repo
        .listSites(organizationId: user?.organizationId)
        .where((s) => s.isActive)
        .toList();
    final siteCutoff = _sitePeriod.cutoff(now);
    final sitePatients = <String, Set<String>>{};
    final siteSessions = <String, int>{};
    for (final c in allConsultations) {
      if (c.visitDate.isBefore(siteCutoff)) continue;
      siteSessions[c.siteId] = (siteSessions[c.siteId] ?? 0) + 1;
      (sitePatients[c.siteId] ??= <String>{}).add(c.patientId);
    }
    final siteStats = sites
        .map((s) => _SiteStat(
              name: s.name,
              patients: sitePatients[s.id]?.length ?? 0,
              sessions: siteSessions[s.id] ?? 0,
            ))
        .where((s) => s.patients > 0 || s.sessions > 0)
        .toList()
      ..sort((a, b) => b.sessions.compareTo(a.sessions));

    // Carga por Kurador, filtrado por _kuradorPeriod: sesiones y pacientes
    // distintos atendidos por cada uno en el periodo.
    final staff = repo
        .listStaff(organizationId: user?.organizationId)
        .where((s) => s.isActive)
        .toList();
    final kCutoff = _kuradorPeriod.cutoff(now);
    final kSessions = <String, int>{};
    final kPatients = <String, Set<String>>{};
    for (final c in allConsultations) {
      if (c.visitDate.isBefore(kCutoff)) continue;
      kSessions[c.staffId] = (kSessions[c.staffId] ?? 0) + 1;
      (kPatients[c.staffId] ??= <String>{}).add(c.patientId);
    }
    final loads = staff
        .map((s) => _StaffLoad(
              name: s.fullName,
              role: s.roleTitle,
              patients: kPatients[s.id]?.length ?? 0,
              sessions: kSessions[s.id] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.sessions.compareTo(a.sessions));
    final maxSessions = loads.fold<int>(1, (m, l) => l.sessions > m ? l.sessions : m);

    return [
      ..._greeting(context, user, 'Supervisión del centro'),
      const SizedBox(height: 20),
      _HeroCard(
        activePatients: activePatients,
        activeWounds: activeWounds,
        dangerCount: red,
        onTapAttention: () => _openPatients(status: ProgressStatus.danger),
      ),
      const SizedBox(height: 20),
      _KpiRow(kpis: [
        _Kpi(icon: Icons.people, label: 'Pacientes activos', value: '$activePatients', color: t.info),
        _Kpi(icon: Icons.healing, label: 'Heridas activas', value: '$activeWounds', color: t.info),
        _Kpi(icon: Icons.trending_up, label: 'En avance', value: '$closureRate%', color: t.statusSuccess),
        _Kpi(
            icon: Icons.report_gmailerrorred_rounded,
            label: 'Requieren atención',
            value: '$red',
            color: t.statusDanger),
      ]),
      const SizedBox(height: 28),
      if (triage.isEmpty)
        const _EmptyDashboard(isAdmin: true)
      else
        // En escritorio los bloques se reparten en varias columnas (no ocupan
        // todo el ancho); en móvil quedan en una sola.
        ResponsiveColumns(
          blocks: [
            _sectionBlock(
              context,
              icon: Icons.donut_small_outlined,
              title: 'Estado de trayectoria del centro',
              count: triage.length,
              child: _StatusDonut(green: green, amber: amber, red: red, noData: noData),
            ),
            if (etiologies.isNotEmpty)
              _sectionBlock(
                context,
                icon: Icons.category_outlined,
                title: 'Tipos de lesión',
                count: etiologies.length,
                child: _CategoryBars(
                  entries: [
                    for (final e in etiologies) _BarDatum(label: e.key.label, value: e.value)
                  ],
                  color: t.brandPrimary,
                ),
              ),
            _sectionBlock(
              context,
              icon: Icons.location_on_outlined,
              title: 'Pacientes y sesiones por sitio',
              count: siteStats.length,
              filter: _PeriodChips(
                value: _sitePeriod,
                onChanged: (p) => setState(() => _sitePeriod = p),
              ),
              child: siteStats.isEmpty
                  ? Text('Sin actividad registrada en este periodo.',
                      style: TextStyle(color: t.textSecondary))
                  : _SiteBars(stats: siteStats),
            ),
            _sectionBlock(
              context,
              icon: Icons.groups_outlined,
              title: 'Carga por Kurador',
              count: loads.length,
              filter: _PeriodChips(
                value: _kuradorPeriod,
                onChanged: (p) => setState(() => _kuradorPeriod = p),
              ),
              child: loads.isEmpty
                  ? Text('Sin personal sanitario activo en el centro.',
                      style: TextStyle(color: t.textSecondary))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < loads.length; i++)
                          _StaffLoadRow(
                            load: loads[i],
                            maxSessions: maxSessions,
                            showDivider: i > 0,
                          ),
                      ],
                    ),
            ),
          ],
        ),
    ];
  }

  /// Bloque UNIFICADO: encabezado + (filtro opcional) + contenido, todo en una
  /// sola tarjeta glass.
  Widget _sectionBlock(
    BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
    required Widget child,
    Widget? filter,
  }) {
    final t = BrandTokens.of(context);
    return KuraGlassCard(
      blur: false,
      borderRadius: 18,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: t.info.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: t.info, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: t.info.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$count',
                    style: TextStyle(fontWeight: FontWeight.w800, color: t.info)),
              ),
            ],
          ),
          if (filter != null) ...[const SizedBox(height: 12), filter],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Paciente + su resumen de heridas + el peor estatus de trayectoria,
/// calculado una sola vez y compartido por metricas y secciones.
class _Triage {
  final Patient patient;
  final PatientWoundSummary summary;
  final PatientProgressStatus progress;

  const _Triage({required this.patient, required this.summary, required this.progress});

  ProgressStatus get worst => progress.worst;
}

/// Hero del dashboard: banner oscuro con degradado de marca y el resumen del
/// día (estilo mockup). El CTA es una acción clínica real (ir a "Requieren
/// atención"), no una "agenda del día".
class _HeroCard extends StatelessWidget {
  final int activePatients;
  final int activeWounds;
  final int dangerCount;
  final VoidCallback onTapAttention;

  const _HeroCard({
    required this.activePatients,
    required this.activeWounds,
    required this.dangerCount,
    required this.onTapAttention,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    // Se usa el ancho REAL disponible para el hero (constraints), NO el de la
    // pantalla: en un layout multi-columna el hero puede ser angosto aunque la
    // pantalla sea ancha. Usar el ancho de pantalla reservaba espacio para la
    // ilustración y aplastaba el texto -> overflow / pantalla en blanco.
    // En anchos < 600 se oculta la ilustración (móvil) y los KPIs ocupan todo
    // el ancho en tercios iguales; en anchos grandes el arte se mantiene.
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final showArt = width.isFinite && width >= 600;
      final art = showArt
          ? ((width - 32) * 0.34).clamp(180.0, 320.0).toDouble()
          : 0.0;
      // Stack sin recorte: la ilustración 3D DESBORDA el recuadro morado,
      // sobresaliendo por arriba y un poco a la derecha.
      return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.heroTop, t.heroBottom],
            ),
            borderRadius: AppRadii.lgR,
            boxShadow: [
              BoxShadow(
                color: t.heroTop.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            // Reserva a la derecha solo cuando hay arte (escritorio); en móvil
            // el texto usa todo el ancho.
            padding: EdgeInsets.only(right: showArt ? art * 0.72 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hoy',
                  style: TextStyle(
                    color: t.onBrand.withOpacity(0.70),
                    fontSize: AppType.label,
                    fontWeight: AppType.semibold,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        value: '$activePatients',
                        label: 'pacientes\nactivos',
                        color: t.onBrand,
                      ),
                    ),
                    _HeroDivider(color: t.onBrand.withOpacity(0.20)),
                    Expanded(
                      child: _HeroStat(
                        value: '$activeWounds',
                        label: 'heridas en\ntratamiento',
                        color: t.onBrand,
                      ),
                    ),
                    _HeroDivider(color: t.onBrand.withOpacity(0.20)),
                    Expanded(
                      child: _HeroStat(
                        value: '$dangerCount',
                        label: 'requieren\natención',
                        color: dangerCount > 0 ? const Color(0xFFFF7A90) : t.onBrand,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: t.onBrand,
                    borderRadius: AppRadii.pillR,
                    child: InkWell(
                      onTap: onTapAttention,
                      borderRadius: AppRadii.pillR,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.priority_high_rounded, size: 18, color: t.brandPrimary),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                              child: Text('Requieren atención',
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: TextStyle(
                                      color: t.brandPrimary, fontWeight: AppType.bold)),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(Icons.chevron_right, size: 18, color: t.brandPrimary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
          if (showArt)
            Positioned(
              right: -art * 0.06,
              top: -art * 0.16,
              child: SizedBox(
                width: art,
                height: art,
                child: _HeroArt(fallbackColor: t.onBrand),
              ),
            ),
        ],
      );
    });
  }
}

/// Ilustración 3D del hero. Usa el asset si existe; si aún no está, cae al
/// glifo decorativo (para no romper la pantalla).
class _HeroArt extends StatelessWidget {
  final Color fallbackColor;
  const _HeroArt({required this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    // Llena la caja que le da el hero (tamaño proporcional al ancho).
    return Image.asset(
      'assets/images/hero_bandage.png',
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Center(child: _HeroGlyph(color: fallbackColor)),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _HeroStat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: AppType.display, fontWeight: AppType.extrabold)),
        Text(label,
            style: TextStyle(
                color: color.withOpacity(0.75), fontSize: AppType.caption, height: 1.1)),
      ],
    );
  }
}

class _HeroDivider extends StatelessWidget {
  final Color color;
  const _HeroDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      color: color,
    );
  }
}

/// Motivo decorativo del hero (evoca el apósito del mockup) construido con
/// formas translúcidas — sin assets ni paquetes.
class _HeroGlyph extends StatelessWidget {
  final Color color;
  const _HeroGlyph({required this.color});

  Widget _square(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(opacity),
          borderRadius: AppRadii.mdR,
          border: Border.all(color: color.withOpacity(0.20)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(right: 10, top: 2, child: _square(52, 0.10)),
          Positioned(right: 0, bottom: 0, child: _square(64, 0.16)),
          Icon(Icons.healing, size: 34, color: color.withOpacity(0.92)),
        ],
      ),
    );
  }
}

/// Encabezado de seccion con icono acentuado y contador.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return KuraGlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ),
      ],
      ),
    );
  }
}

/// Estado vacio POSITIVO de la seccion de atencion.
class _AttentionEmpty extends StatelessWidget {
  const _AttentionEmpty();

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      decoration: BoxDecoration(
        color: t.statusSuccess.withOpacity(0.08),
        borderRadius: AppRadii.mdR,
        border: Border.all(color: t.statusSuccess.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: t.statusSuccess),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Sin pacientes que requieran atención por ahora ✅',
              style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vacio cuando el usuario no tiene ningun paciente todavia.
class _EmptyDashboard extends StatelessWidget {
  final bool isAdmin;
  const _EmptyDashboard({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: t.surface.withOpacity(0.5),
        borderRadius: AppRadii.mdR,
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 44, color: t.textDisabled),
          const SizedBox(height: AppSpacing.md),
          Text(
            isAdmin
                ? 'Aún no hay pacientes en el centro.'
                : 'Aún no tienes pacientes asignados.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Usa "Nuevo paciente" para registrar el primero.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.label, color: t.textDisabled),
          ),
        ],
      ),
    );
  }
}

/// Fondo del dashboard: un degradado crema muy sutil (con un toque del
/// acento Kura) mas 2-3 "blobs" de color difuso detras del contenido. Le da
/// algo que refractar al vidrio de las tarjetas sin saturar la pantalla.
/// Los blobs usan RadialGradient (bordes suaves, sin BackdropFilter) para
/// ser baratos de pintar; el Stack recorta lo que se sale de pantalla.
class _DashboardBackground extends StatelessWidget {
  const _DashboardBackground();

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            t.background,
            // "Un toque del acento Kura muy tenue" como ambiente (no acción).
            Color.alphaBlend(t.brandPrimary.withOpacity(0.05), t.background),
          ],
        ),
      ),
      // Blobs ambientales en tonos de marca/informativo (nunca colores de
      // estado clínico, que no son decorativos).
      child: Stack(
        children: [
          Positioned(top: -80, left: -60, child: _Blob(t.brandPrimary, 260, 0.08)),
          Positioned(top: 160, right: -90, child: _Blob(t.info, 300, 0.07)),
          Positioned(bottom: -70, left: -30, child: _Blob(t.info, 240, 0.05)),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _Blob(this.color, this.size, this.opacity);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(opacity), color.withOpacity(0)],
          ),
        ),
      ),
    );
  }
}

// ===================== Clínico: búsqueda + accesos =====================

/// Barra de búsqueda (abre la lista de pacientes, donde vive la búsqueda real)
/// + accesos rápidos a destinos frecuentes.
class _QuickAccessBar extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onReports;
  const _QuickAccessBar({required this.onSearch, required this.onReports});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Material(
            color: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.pillR,
              side: BorderSide(color: t.border),
            ),
            child: InkWell(
              onTap: onSearch,
              borderRadius: AppRadii.pillR,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: t.textSecondary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Buscar paciente', style: TextStyle(color: t.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Tooltip(
          message: 'Reportes',
          child: Material(
            color: t.brandPrimary.withOpacity(0.10),
            borderRadius: AppRadii.mdR,
            child: InkWell(
              onTap: onReports,
              borderRadius: AppRadii.mdR,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(Icons.description_outlined, color: t.brandPrimary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ===================== Clínico: tile "reciente" con sparkline =====================

class _RecentPatientTile extends StatelessWidget {
  final _Triage triage;
  final List<double> series;
  final VoidCallback onTap;
  const _RecentPatientTile({
    required this.triage,
    required this.series,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final p = triage.patient;
    final statusColor = triage.worst.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KuraGlassCard(
        blur: false,
        borderRadius: 18,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: t.info.withOpacity(0.12),
                  child: Text(p.fullName.isNotEmpty ? p.fullName[0] : '?',
                      style: TextStyle(color: t.info, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${p.folio} · ${p.age ?? '?'} años',
                          style: TextStyle(fontSize: 12, color: t.textSecondary)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (series.length >= 2)
                            _WoundSparkline(values: series, color: statusColor)
                          else
                            Text('Sin datos de evolución',
                                style: TextStyle(fontSize: 11, color: t.textDisabled)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(triage.worst.shortLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: statusColor,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: t.textDisabled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini-gráfica de trayectoria (área de la herida vs. tiempo). Y invertida:
/// área menor (mejor) arriba. Coloreada según el estatus del semáforo.
class _WoundSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  const _WoundSparkline({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 26,
      child: CustomPaint(painter: _SparklinePainter(values, color)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);
    double yFor(double v) => size.height - ((v - minV) / range) * size.height;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = yFor(values[i]);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      Offset(dx * (values.length - 1), yFor(values.last)),
      2.5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}

// ===================== Admin: KPIs =====================

class _Kpi {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _KpiRow extends StatelessWidget {
  final List<_Kpi> kpis;
  const _KpiRow({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w < 720 ? 2 : 4;
        final itemW = (w - (cols - 1) * 12 - 1) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: kpis
              .map((k) => SizedBox(
                    width: itemW,
                    child: KuraGlassCard(
                      blur: false,
                      borderRadius: 18,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: k.color.withOpacity(0.16),
                              borderRadius: AppRadii.mdR,
                            ),
                            child: Icon(k.icon, color: k.color),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(k.value,
                                    style: const TextStyle(
                                        fontSize: AppType.headline,
                                        fontWeight: AppType.extrabold)),
                                Text(k.label,
                                    style: TextStyle(
                                        fontSize: AppType.label,
                                        color: t.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

// ===================== Admin: donut de estatus =====================

class _StatusDonut extends StatelessWidget {
  final int green;
  final int amber;
  final int red;
  final int noData;
  const _StatusDonut({
    required this.green,
    required this.amber,
    required this.red,
    required this.noData,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final total = green + amber + red + noData;
    // Paleta de ESTATUS (reservada, clínica) — siempre acompañada de etiqueta.
    final segs = <(int, Color, String)>[
      (red, t.statusDanger, 'No avanza'),
      (amber, t.statusWarning, 'Con reservas'),
      (green, t.statusSuccess, 'Avanza'),
      (noData, t.statusNeutral, 'Sin datos'),
    ];
    return total == 0
        ? Text('Sin datos de trayectoria aún.',
            style: TextStyle(color: t.textSecondary))
        : Row(
              children: [
                SizedBox(
                  width: 116,
                  height: 116,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      values: [for (final s in segs) s.$1],
                      colors: [for (final s in segs) s.$2],
                      track: t.border,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$total',
                              style: TextStyle(
                                  fontSize: AppType.headline,
                                  fontWeight: AppType.extrabold,
                                  color: t.textPrimary)),
                          Text('pacientes',
                              style: TextStyle(
                                  fontSize: AppType.caption,
                                  color: t.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in segs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LegendDot(color: s.$2, label: s.$3, count: s.$1),
                        ),
                    ],
                  ),
                ),
              ],
            );
  }
}

class _DonutPainter extends CustomPainter {
  final List<int> values;
  final List<Color> colors;
  final Color track;
  _DonutPainter({required this.values, required this.colors, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (math.min(size.width, size.height) - stroke) / 2,
    );
    // Anillo de fondo (track).
    canvas.drawArc(rect, 0, 2 * math.pi, false,
        Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = stroke);
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return;
    var start = -math.pi / 2;
    const gap = 0.03; // separación de 2px entre segmentos
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = (values[i] / total) * 2 * math.pi;
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.colors != colors || old.track != track;
}

// ===================== Admin: barras horizontales =====================

class _BarDatum {
  final String label;
  final int value;
  const _BarDatum({required this.label, required this.value});
}

/// Barras horizontales de magnitud (un solo tono = sin problema de daltonismo),
/// con etiqueta y valor directos.
class _CategoryBars extends StatelessWidget {
  final List<_BarDatum> entries;
  final Color color;
  const _CategoryBars({required this.entries, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final maxV = entries.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == entries.length - 1 ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(entries[i].label,
                            style: const TextStyle(fontSize: AppType.body)),
                      ),
                      const SizedBox(width: 8),
                      Text('${entries[i].value}',
                          style: const TextStyle(fontWeight: AppType.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 8,
                      color: t.border,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: entries[i].value / maxV,
                        child: ColoredBox(color: color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
  }
}

// ===================== Admin: pacientes/sesiones por sitio =====================

class _SiteStat {
  final String name;
  final int patients;
  final int sessions;
  const _SiteStat({required this.name, required this.patients, required this.sessions});
}

class _SiteBars extends StatelessWidget {
  final List<_SiteStat> stats;
  const _SiteBars({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final maxPat = stats.fold<int>(1, (m, s) => s.patients > m ? s.patients : m);
    final maxSes = stats.fold<int>(1, (m, s) => s.sessions > m ? s.sessions : m);
    // 2 series: cromático (marca) vs acromático (gris). Distinguibles bajo
    // cualquier daltonismo (difieren en croma), además de etiqueta directa.
    final sesColor = t.textSecondary;
    Widget dot(Color c) => Container(
        width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    Widget bar(int value, int max, Color color) => Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  height: 10,
                  color: t.border,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value / max,
                    child: ColoredBox(color: color),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 28,
              child: Text('$value',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
              dot(t.brandPrimary),
              const SizedBox(width: 6),
              Text('Pacientes',
                  style: TextStyle(fontSize: AppType.label, color: t.textSecondary)),
              const SizedBox(width: 16),
              dot(sesColor),
              const SizedBox(width: 6),
              Text('Sesiones',
                  style: TextStyle(fontSize: AppType.label, color: t.textSecondary)),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < stats.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == stats.length - 1 ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stats[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  bar(stats[i].patients, maxPat, t.brandPrimary),
                  const SizedBox(height: 6),
                  bar(stats[i].sessions, maxSes, sesColor),
                ],
              ),
            ),
        ],
      );
  }
}

// ===================== Layout multi-columna (escritorio) =====================

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _LegendDot({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text('$label ($count)',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
        ),
      ],
    );
  }
}

// ===================== Admin: carga por Kurador =====================

class _StaffLoad {
  final String name;
  final String role;
  final int patients;
  final int sessions;
  const _StaffLoad({
    required this.name,
    required this.role,
    required this.patients,
    required this.sessions,
  });
}

/// Fila de un Kurador SIN tarjeta propia (vive dentro de la tarjeta unificada
/// del bloque). Barra proporcional a las sesiones del periodo.
class _StaffLoadRow extends StatelessWidget {
  final _StaffLoad load;
  final int maxSessions;
  final bool showDivider;
  const _StaffLoadRow({
    required this.load,
    required this.maxSessions,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final frac =
        maxSessions <= 0 ? 0.0 : (load.sessions / maxSessions).clamp(0.0, 1.0);
    return Column(
      children: [
        if (showDivider) ...[
          const SizedBox(height: 14),
          Divider(height: 1, color: t.border),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: t.info.withOpacity(0.12),
              child: Text(load.name.isNotEmpty ? load.name[0] : '?',
                  style: TextStyle(color: t.info, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(load.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(load.role, style: TextStyle(fontSize: 12, color: t.textSecondary)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 6,
                      backgroundColor: t.border,
                      valueColor: AlwaysStoppedAnimation<Color>(t.brandPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${load.sessions}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                Text('sesiones · ${load.patients} pac.',
                    style: TextStyle(fontSize: 11, color: t.textSecondary)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ===================== Hospital: Inicio de prevención =====================

/// Entrada de "requieren atención" del Inicio hospitalario: paciente + su banda
/// de Braden + internamiento + tareas vencidas + si es alto riesgo sin revisar.
class _HospEntry {
  final Patient patient;
  final RiskLevel? band;
  final PatientAdmission? admission;
  final int overdue;
  final bool unreviewed;
  const _HospEntry({
    required this.patient,
    required this.band,
    required this.admission,
    required this.overdue,
    required this.unreviewed,
  });
}

/// Accesos rápidos del Inicio hospitalario a los flujos de prevención.
class _HospitalQuickAccess extends StatelessWidget {
  final VoidCallback onRondas;
  final VoidCallback onTablero;
  final VoidCallback onDashboard;
  const _HospitalQuickAccess({
    required this.onRondas,
    required this.onTablero,
    required this.onDashboard,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _HospitalQuickAction(
              icon: Icons.checklist_outlined, label: 'Rondas', onTap: onRondas),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HospitalQuickAction(
              icon: Icons.shield_outlined, label: 'Tablero', onTap: onTablero),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HospitalQuickAction(
              icon: Icons.insights_outlined,
              label: 'Dashboard',
              onTap: onDashboard),
        ),
      ],
    );
  }
}

class _HospitalQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HospitalQuickAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Material(
      color: t.brandPrimary.withOpacity(0.10),
      borderRadius: AppRadii.mdR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.mdR,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: t.brandPrimary),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: t.brandPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: AppType.label)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra segmentada de distribución por banda de Braden + leyenda.
class _RiskBandsBar extends StatelessWidget {
  final int alto;
  final int medio;
  final int bajo;
  final int sinValoracion;
  const _RiskBandsBar({
    required this.alto,
    required this.medio,
    required this.bajo,
    required this.sinValoracion,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final segs = <(String, int, Color)>[
      ('Alto', alto, riskLevelColor(RiskLevel.alto)),
      ('Medio', medio, riskLevelColor(RiskLevel.medio)),
      ('Bajo', bajo, riskLevelColor(RiskLevel.bajo)),
      ('Sin valoración', sinValoracion, t.statusNeutral),
    ];
    final total = alto + medio + bajo + sinValoracion;
    if (total == 0) {
      return Text('Sin pacientes internados con valoración.',
          style: TextStyle(color: t.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              for (final s in segs)
                if (s.$2 > 0)
                  Expanded(flex: s.$2, child: Container(height: 12, color: s.$3)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final s in segs)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration:
                          BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${s.$1}: ${s.$2}',
                      style: TextStyle(fontSize: 13, color: t.textSecondary)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Tile de paciente que requiere atención en el Inicio hospitalario. Abre la
/// ficha de riesgo (Braden / rondas) del paciente.
class _HospitalAttentionTile extends StatelessWidget {
  final _HospEntry entry;
  final VoidCallback onTap;
  const _HospitalAttentionTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final color =
        entry.band != null ? riskLevelColor(entry.band!) : t.statusNeutral;
    final levelLabel = entry.band?.label ?? 'Sin valoración';
    final loc = entry.admission?.locationLabel ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KuraGlassCard(
        blur: false,
        borderRadius: 18,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.16),
                  child: Icon(Icons.shield_outlined, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.patient.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (loc.isNotEmpty)
                        Text(loc,
                            style: TextStyle(
                                fontSize: 12, color: t.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MiniChip(label: levelLabel, color: color),
                          if (entry.unreviewed)
                            _MiniChip(
                                label: 'Sin revisar', color: t.statusDanger),
                          if (entry.overdue > 0)
                            _MiniChip(
                                label:
                                    '${entry.overdue} vencida${entry.overdue == 1 ? '' : 's'}',
                                color: t.statusWarning),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: t.textDisabled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Estado vacío del Inicio hospitalario (sin pacientes internados).
class _HospitalEmpty extends StatelessWidget {
  const _HospitalEmpty();

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: t.surface.withOpacity(0.5),
        borderRadius: AppRadii.mdR,
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Icon(Icons.local_hotel_outlined, size: 44, color: t.textDisabled),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Aún no hay pacientes internados en el centro.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Registra un internamiento y una valoración de Braden para poblar el '
            'tablero de prevención.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.label, color: t.textDisabled),
          ),
        ],
      ),
    );
  }
}

/// Chips de filtro de temporalidad (mes actual / 30 / 14 / 7 días) para los
/// indicadores de actividad del admin.
class _PeriodChips extends StatelessWidget {
  final _Period value;
  final ValueChanged<_Period> onChanged;
  const _PeriodChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in _Period.values)
          ChoiceChip(
            label: Text(p.label),
            selected: p == value,
            onSelected: (_) => onChanged(p),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: p == value ? FontWeight.w700 : FontWeight.w500,
              color: p == value ? t.brandPrimary : t.textSecondary,
            ),
            selectedColor: t.brandPrimary.withOpacity(0.12),
            backgroundColor: t.surface,
            side: BorderSide(
                color: p == value ? t.brandPrimary.withOpacity(0.4) : t.border),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}
