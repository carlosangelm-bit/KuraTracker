import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/vac_therapy.dart';
import '../../services/data_repository.dart';
import 'vac_therapy_form.dart';

/// Módulo Terapia VAC (Fase 1): lista de terapias del centro. La terapia sigue
/// al paciente (transversal: hospital / clínica / domicilio). Toca "+" para
/// registrar una nueva eligiendo al paciente; toca una tarjeta para ver el
/// detalle y su bitácora.
class VacTherapiesScreen extends ConsumerWidget {
  const VacTherapiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final orgId = ref.watch(sessionProvider).user?.organizationId;
    final t = BrandTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terapia VAC'),
        actions: const [UserMenuButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newTherapy(context, ref, orgId),
        icon: const Icon(Icons.add),
        label: const Text('Nueva terapia'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final all = repo.listVacTherapies(organizationId: orgId);
          final active = all.where((x) => x.isActive).toList();
          final past = all.where((x) => !x.isActive).toList();
          if (all.isEmpty) {
            return const _Empty();
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (active.isNotEmpty) ...[
                _Label('Activas (${active.length})'),
                ...active.map((x) => _TherapyCard(repo: repo, therapy: x, t: t)),
              ],
              if (past.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Label('Finalizadas / suspendidas (${past.length})'),
                ...past.map((x) => _TherapyCard(repo: repo, therapy: x, t: t)),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _newTherapy(
      BuildContext context, WidgetRef ref, String? orgId) async {
    if (orgId == null) return;
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    if (repo == null) return;
    final patients = repo.listAllPatients()
        .where((p) => p.organizationId == orgId)
        .toList()
      ..sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    if (patients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay pacientes en este centro.')));
      return;
    }
    final patientId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Paciente para la terapia',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final p in patients)
                ListTile(
                  title: Text(p.fullName),
                  onTap: () => Navigator.of(context).pop(p.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (patientId == null || !context.mounted) return;
    await showVacTherapyForm(context, ref, orgId: orgId, patientId: patientId);
  }
}

class _TherapyCard extends StatelessWidget {
  final DataRepository repo;
  final VacTherapy therapy;
  final BrandTokens t;
  const _TherapyCard({required this.repo, required this.therapy, required this.t});

  @override
  Widget build(BuildContext context) {
    final patient = repo.getPatient(therapy.patientId);
    final statusColor = therapy.status == VacTherapyStatus.activa
        ? t.statusSuccess
        : therapy.status == VacTherapyStatus.suspendida
            ? t.statusDanger
            : t.textSecondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.push('/vac/${therapy.id}'),
        leading: CircleAvatar(
          backgroundColor: t.brandPrimary.withValues(alpha: 0.12),
          child: Icon(Icons.healing_outlined, color: t.brandPrimary),
        ),
        title: Text(patient?.fullName ?? 'Paciente',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(therapy.equipment.label, style: const TextStyle(fontSize: 12)),
            if (therapy.settingsLabel.isNotEmpty)
              Text(therapy.settingsLabel,
                  style: TextStyle(fontSize: 12, color: t.textSecondary)),
            if (therapy.currentLocation != null)
              Text(therapy.currentLocation!.label,
                  style: TextStyle(fontSize: 12, color: t.textSecondary)),
          ],
        ),
        trailing: Chip(
          label: Text(therapy.status.label,
              style: TextStyle(fontSize: 11, color: statusColor)),
          backgroundColor: statusColor.withValues(alpha: 0.10),
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: BrandTokens.of(context).textSecondary)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.healing_outlined, size: 40),
              SizedBox(height: 10),
              Text('Sin terapias VAC registradas.\nToca "Nueva terapia" para empezar.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
