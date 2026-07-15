import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../models/patient.dart';
import '../../models/wound.dart';
import '../../services/data_repository.dart';
import '../patients/patient_list_tile.dart';
import '../patients/patient_wound_summary.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = session.user;

    return Scaffold(
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final patients = user?.role == AppRole.admin
              ? repo.listAllPatients()
              : (user?.staffId != null
                  ? repo.listPatientsForStaff(user!.staffId!)
                  : <Patient>[]);

          final allWounds = patients
              .expand((p) => repo.listWoundsForPatient(p.id))
              .where((w) => w.isActive)
              .toList();

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      'Hola, ${user?.fullName.split(' ').first ?? ''} 👋',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Resumen de tu actividad clínica en Kura+',
                      style: TextStyle(color: KuraColors.darkText.withOpacity(0.6)),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _StatCard(
                          icon: Icons.people,
                          label: 'Pacientes activos',
                          value: '${patients.where((p) => p.isActive).length}',
                          color: KuraColors.primary,
                        ),
                        _StatCard(
                          icon: Icons.healing,
                          label: 'Heridas en tratamiento',
                          value: '${allWounds.length}',
                          color: KuraColors.infoBlue,
                        ),
                        _StatCard(
                          icon: Icons.warning_amber_rounded,
                          label: 'Alertas activas',
                          value: '${_countUrgentAlerts(repo, allWounds)}',
                          color: KuraColors.danger,
                        ),
                        if (user?.premiumEnabled == true)
                          _StatCard(
                            icon: Icons.auto_awesome,
                            label: 'Protocolo Kura+',
                            value: 'Activo',
                            color: KuraColors.success,
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text('Pacientes recientes',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                  ]),
                ),
              ),
              if (patients.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('No tienes pacientes asignados aún.')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final patient = patients[index];
                        // Mismo componente que la vista Lista de
                        // PatientsListScreen (rediseno): consistencia de
                        // chips de etiologia entre Dashboard y Pacientes.
                        // Sin acciones rapidas aqui a proposito -- este es
                        // solo un resumen, la pantalla completa de
                        // Pacientes es donde se actua.
                        final summary = PatientWoundSummary.compute(repo, patient.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: PatientListTile(
                            patient: patient,
                            summary: summary,
                            onTap: () => context.go('/patients/${patient.id}'),
                          ),
                        );
                      },
                      childCount: patients.length > 6 ? 6 : patients.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: KuraColors.primary,
        onPressed: () => context.go('/patients/new'),
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo paciente'),
      ),
    );
  }

  int _countUrgentAlerts(DataRepository repo, List<Wound> wounds) {
    var count = 0;
    for (final w in wounds) {
      final recs = repo.listRecommendationsForWound(w.id);
      for (final r in recs) {
        final alertas = (r['alertas'] as List?) ?? [];
        if (alertas.isNotEmpty) count++;
      }
    }
    return count;
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KuraColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: KuraColors.darkText.withOpacity(0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


