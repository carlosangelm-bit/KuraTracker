import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show kFloatingNavBarHeight;
import '../../core/widgets/kura_primary_fab.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/sheehan_decision_style.dart';
import '../../models/app_user.dart';
import '../../models/patient.dart';
import '../../services/data_repository.dart';
import 'patient_grid_card.dart';
import 'patient_list_tile.dart';
import 'patient_progress_status.dart';
import 'patient_wound_summary.dart';
import 'patients_filter_bar.dart';
import 'patients_view_preferences.dart';
import 'wound_picker_sheet.dart';

/// Pantalla de pacientes con selector de vista Lista/Tarjeta (rediseno):
/// - Lista: la vista original (ListTile en columna), ahora con chips de
///   etiologia de heridas activas.
/// - Tarjeta: GridView responsivo con acciones rapidas de Valoracion y
///   Seguimiento.
///
/// Ambas vistas comparten los mismos filtros (busqueda, etiologia, estado,
/// sitio) y respetan el aislamiento de acceso existente:
/// listPatientsForStaff(staffId) para clinico, listAllPatients() para
/// admin/master (acotado por RLS de organizacion en Supabase, 0011).
///
/// La vista elegida y los filtros estructurados (NO la busqueda de texto,
/// ver PatientsViewPreferences.fromJson) se persisten en
/// shared_preferences para sobrevivir un reload/reinicio.
class PatientsListScreen extends ConsumerStatefulWidget {
  const PatientsListScreen({super.key});

  @override
  ConsumerState<PatientsListScreen> createState() => PatientsListScreenState();
}

class PatientsListScreenState extends ConsumerState<PatientsListScreen> {
  PatientsViewPreferences _prefs = const PatientsViewPreferences();
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final loaded = await PatientsViewPreferencesStore.load();
    if (mounted) {
      setState(() {
        _prefs = loaded;
        _prefsLoaded = true;
      });
    }
  }

  void _updatePrefs(PatientsViewPreferences Function(PatientsViewPreferences) update) {
    setState(() => _prefs = update(_prefs));
    // La busqueda de texto no se persiste (ver fromJson), pero guardar el
    // objeto completo cada vez es inocuo: al recargar simplemente vuelve
    // vacia. Se persiste de forma "fire and forget": la UI ya reflejo el
    // cambio via setState, no hace falta bloquear la interaccion en el
    // await de disco.
    unawaited(PatientsViewPreferencesStore.save(_prefs));
  }

  List<Patient> _applyFilters(
    List<Patient> patients,
    DataRepository repo,
    Map<String, PatientWoundSummary> summaries,
    Map<String, PatientProgressStatus> progressStatuses,
  ) {
    var result = patients;

    if (_prefs.query.isNotEmpty) {
      final q = _prefs.query.toLowerCase();
      result = result
          .where((p) =>
              p.fullName.toLowerCase().contains(q) || p.folio.toLowerCase().contains(q))
          .toList();
    }

    if (_prefs.siteId != null) {
      result = result.where((p) => p.primarySiteId == _prefs.siteId).toList();
    }

    if (_prefs.statusFilter != PatientsStatusFilter.all) {
      result = result.where((p) {
        final hasActive = summaries[p.id]?.hasActiveWounds ?? false;
        return _prefs.statusFilter == PatientsStatusFilter.withActiveWounds
            ? hasActive
            : !hasActive;
      }).toList();
    }

    if (_prefs.etiologies.isNotEmpty) {
      result = result.where((p) {
        final etiologies = summaries[p.id]?.etiologies ?? const <Etiologia>[];
        return etiologies.any(_prefs.etiologies.contains);
      }).toList();
    }

    if (_prefs.progressStatuses.isNotEmpty) {
      result = result.where((p) {
        final worst = progressStatuses[p.id]?.worst ?? ProgressStatus.noData;
        return _prefs.progressStatuses.contains(worst);
      }).toList();
    }

    return result;
  }

  Future<void> _goToValoracion(String patientId) async {
    context.go('/patients/$patientId/consultation/new?visitType=valoracion');
  }

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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = session.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pacientes'),
        actions: [
          if (_prefsLoaded)
            _ViewModeToggle(
              value: _prefs.viewMode,
              onChanged: (mode) => _updatePrefs((p) => p.copyWith(viewMode: mode)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_prefsLoaded
          ? const Center(child: CircularProgressIndicator())
          : repoAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (repo) {
                final allPatients = user?.role == AppRole.admin
                    ? repo.listAllPatients()
                    : (user?.staffId != null
                        ? repo.listPatientsForStaff(user!.staffId!)
                        : <Patient>[]);

                final summaries = <String, PatientWoundSummary>{
                  for (final p in allPatients) p.id: PatientWoundSummary.compute(repo, p.id),
                };

                final progressStatuses = <String, PatientProgressStatus>{
                  for (final p in allPatients)
                    p.id: PatientProgressStatus.compute(
                        repo, summaries[p.id]!.activeWounds),
                };

                final patients =
                    _applyFilters(allPatients, repo, summaries, progressStatuses);
                final sites = repo.listSites();

                return Column(
                  children: [
                    PatientsFilterBar(
                      query: _prefs.query,
                      onQueryChanged: (v) => _updatePrefs((p) => p.copyWith(query: v)),
                      selectedEtiologies: _prefs.etiologies,
                      onEtiologiesChanged: (v) => _updatePrefs((p) => p.copyWith(etiologies: v)),
                      statusFilter: _prefs.statusFilter,
                      onStatusFilterChanged: (v) =>
                          _updatePrefs((p) => p.copyWith(statusFilter: v)),
                      sites: sites,
                      siteId: _prefs.siteId,
                      onSiteChanged: (v) => _updatePrefs((p) => p.copyWith(siteId: v)),
                      selectedProgressStatuses: _prefs.progressStatuses,
                      onProgressStatusesChanged: (v) =>
                          _updatePrefs((p) => p.copyWith(progressStatuses: v)),
                      onClearFilters: () => _updatePrefs((p) => const PatientsViewPreferences()
                          .copyWith(viewMode: p.viewMode, query: p.query)),
                      hasActiveFilters: _prefs.hasActiveFilters,
                    ),
                    Expanded(
                      child: patients.isEmpty
                          ? const Center(child: Text('Sin pacientes.'))
                          : _prefs.viewMode == PatientsViewMode.list
                              ? _PatientsListView(
                                  patients: patients,
                                  summaries: summaries,
                                  progressStatuses: progressStatuses,
                                  onOpenPatient: (id) => context.go('/patients/$id'),
                                  onValoracion: _goToValoracion,
                                  onSeguimiento: (id) => _goToSeguimiento(repo, id),
                                )
                              : _PatientsGridView(
                                  patients: patients,
                                  summaries: summaries,
                                  progressStatuses: progressStatuses,
                                  onOpenPatient: (id) => context.go('/patients/$id'),
                                  onValoracion: _goToValoracion,
                                  onSeguimiento: (id) => _goToSeguimiento(repo, id),
                                ),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: KuraPrimaryFab(
        onPressed: () => context.go('/patients/new'),
        icon: Icons.person_add,
        label: 'Nuevo paciente',
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  final PatientsViewMode value;
  final ValueChanged<PatientsViewMode> onChanged;

  const _ViewModeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value == PatientsViewMode.list ? 'Cambiar a vista Tarjeta' : 'Cambiar a vista Lista',
      child: IconButton(
        key: const Key('patients_view_mode_toggle'),
        icon: Icon(value == PatientsViewMode.list
            ? Icons.grid_view_outlined
            : Icons.view_list_outlined),
        onPressed: () => onChanged(
          value == PatientsViewMode.list ? PatientsViewMode.grid : PatientsViewMode.list,
        ),
      ),
    );
  }
}

class _PatientsListView extends StatelessWidget {
  final List<Patient> patients;
  final Map<String, PatientWoundSummary> summaries;
  final Map<String, PatientProgressStatus> progressStatuses;
  final ValueChanged<String> onOpenPatient;
  final ValueChanged<String> onValoracion;
  final ValueChanged<String> onSeguimiento;

  const _PatientsListView({
    required this.patients,
    required this.summaries,
    required this.progressStatuses,
    required this.onOpenPatient,
    required this.onValoracion,
    required this.onSeguimiento,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('patients_list_view'),
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        MediaQuery.of(context).viewPadding.bottom + kFloatingNavBarHeight + 24,
      ),
      itemCount: patients.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = patients[i];
        final summary = summaries[p.id]!;
        return PatientListTile(
          patient: p,
          summary: summary,
          progressStatus: progressStatuses[p.id]!,
          onTap: () => onOpenPatient(p.id),
          onValoracion: () => onValoracion(p.id),
          onSeguimiento: () => onSeguimiento(p.id),
        );
      },
    );
  }
}

class _PatientsGridView extends StatelessWidget {
  final List<Patient> patients;
  final Map<String, PatientWoundSummary> summaries;
  final Map<String, PatientProgressStatus> progressStatuses;
  final ValueChanged<String> onOpenPatient;
  final ValueChanged<String> onValoracion;
  final ValueChanged<String> onSeguimiento;

  const _PatientsGridView({
    required this.patients,
    required this.summaries,
    required this.progressStatuses,
    required this.onOpenPatient,
    required this.onValoracion,
    required this.onSeguimiento,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('patients_grid_view'),
      builder: (context, constraints) {
        // Responsivo: 1 columna en movil angosto, 2-4 en pantallas anchas.
        final width = constraints.maxWidth;
        final crossAxisCount = width < 560
            ? 1
            : width < 900
                ? 2
                : width < 1300
                    ? 3
                    : 4;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            MediaQuery.of(context).viewPadding.bottom + kFloatingNavBarHeight + 24,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 250,
          ),
          itemCount: patients.length,
          itemBuilder: (context, i) {
            final p = patients[i];
            final summary = summaries[p.id]!;
            return PatientGridCard(
              patient: p,
              summary: summary,
              progressStatus: progressStatuses[p.id]!,
              onTap: () => onOpenPatient(p.id),
              onValoracion: () => onValoracion(p.id),
              onSeguimiento: () => onSeguimiento(p.id),
            );
          },
        );
      },
    );
  }
}
