import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../services/data_repository.dart';
import '../prevention_agenda/prevention_agenda_screen.dart' show PreventiveTasksView;

/// Inicio del CUIDADOR (rol cuidador, Fase 3). Vista restringida: solo los
/// pacientes que el centro le asignó (caregiver_patient_assignments) y sus
/// propias tareas preventivas. Todo lo clínico es de SOLO LECTURA (RLS 0042).
class CaregiverHomeScreen extends ConsumerStatefulWidget {
  const CaregiverHomeScreen({super.key});

  @override
  ConsumerState<CaregiverHomeScreen> createState() =>
      _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends ConsumerState<CaregiverHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Monitoreo del cuidador'),
          actions: const [UserMenuButton()],
          bottom: const TabBar(tabs: [
            Tab(text: 'Mis tareas'),
            Tab(text: 'Pacientes'),
          ]),
        ),
        body: repoAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
          data: (repo) {
            final tasks =
                repo.listPreventiveTasks(assigneeProfileId: user?.id);
            final patientIds =
                user == null ? <String>[] : repo.patientIdsForCaregiver(user.id);
            return TabBarView(
              children: [
                PreventiveTasksView(
                  repo: repo,
                  tasks: tasks,
                  byProfileId: user?.id,
                  staffId: null, // el cuidador no tiene staff
                  onChanged: () => setState(() {}),
                ),
                _PatientsTab(repo: repo, patientIds: patientIds),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PatientsTab extends StatelessWidget {
  final DataRepository repo;
  final List<String> patientIds;
  const _PatientsTab({required this.repo, required this.patientIds});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    if (patientIds.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'El centro aún no te ha asignado pacientes para monitorear.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: patientIds.map((id) {
        final p = repo.getPatient(id);
        if (p == null) return const SizedBox.shrink();
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: t.brandPrimary.withOpacity(0.12),
              child: Icon(Icons.person_outline, color: t.brandPrimary),
            ),
            title: Text(p.fullName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/caregiver/patient/$id'),
          ),
        );
      }).toList(),
    );
  }
}
