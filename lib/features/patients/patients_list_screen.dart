import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../services/data_repository.dart';

class PatientsListScreen extends ConsumerStatefulWidget {
  const PatientsListScreen({super.key});

  @override
  ConsumerState<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends ConsumerState<PatientsListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = session.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Pacientes')),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          var patients = user?.role == AppRole.admin
              ? repo.listAllPatients()
              : (user?.staffId != null
                  ? repo.listPatientsForStaff(user!.staffId!)
                  : []);

          if (_query.isNotEmpty) {
            final q = _query.toLowerCase();
            patients = patients
                .where((p) =>
                    p.fullName.toLowerCase().contains(q) || p.folio.toLowerCase().contains(q))
                .toList();
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre o folio (EXP2025-...)',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: patients.isEmpty
                    ? const Center(child: Text('Sin pacientes.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: patients.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final p = patients[i];
                          final wounds = repo.listWoundsForPatient(p.id);
                          final activeWounds = wounds.where((w) => w.isActive).length;
                          return Card(
                            child: ListTile(
                              onTap: () => context.go('/patients/${p.id}'),
                              leading: CircleAvatar(
                                backgroundColor: KuraColors.primary.withOpacity(0.12),
                                child: Text(
                                  p.fullName.isNotEmpty ? p.fullName[0] : '?',
                                  style: const TextStyle(
                                      color: KuraColors.primary, fontWeight: FontWeight.w800),
                                ),
                              ),
                              title: Text(p.fullName,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '${p.folio} · ${p.age ?? '?'} años · ${p.sex ?? '-'}'),
                              trailing: Wrap(
                                spacing: 6,
                                children: [
                                  if (p.fragilePatient)
                                    const Tooltip(
                                      message: 'Paciente frágil',
                                      child: Icon(Icons.priority_high,
                                          color: KuraColors.warning, size: 18),
                                    ),
                                  Chip(
                                    label: Text('$activeWounds herida${activeWounds == 1 ? '' : 's'}'),
                                    backgroundColor: activeWounds > 0
                                        ? KuraColors.primary.withOpacity(0.1)
                                        : KuraColors.chipBg,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
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
}
