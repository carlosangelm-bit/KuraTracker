import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../engine/risk/prevention_risk_engine.dart';
import '../../models/app_user.dart';
import '../../models/patient.dart';
import '../../models/patient_admission.dart';
import '../../services/data_repository.dart';
import 'risk_theme.dart';

/// Una entrada del tablero: paciente + su riesgo computado + internamiento.
class _RiskEntry {
  final Patient patient;
  final PreventionRiskResult risk;
  final PatientAdmission? admission;
  const _RiskEntry(this.patient, this.risk, this.admission);
}

/// Tablero de riesgo (módulo de Prevención): lista de pacientes con alertas
/// preventivas o internados, priorizada por nivel de riesgo y filtrable por
/// unidad/servicio. Capa DOCUMENTAL de apoyo a la decisión.
class RiskBoardScreen extends ConsumerStatefulWidget {
  const RiskBoardScreen({super.key});

  @override
  ConsumerState<RiskBoardScreen> createState() => _RiskBoardScreenState();
}

class _RiskBoardScreenState extends ConsumerState<RiskBoardScreen> {
  String? _unitFilter; // null = todas

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final rulesAsync = ref.watch(preventionRulesProvider);
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prevención'),
        actions: const [UserMenuButton()],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) => rulesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error al cargar reglas: $e')),
          data: (catalog) => _buildBoard(context, repo, catalog, user),
        ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context, DataRepository repo,
      PreventionRulesCatalog catalog, AppUser? user) {
    // Base de pacientes: admin/master ven los del centro; clínico, los suyos.
    final basePatients =
        (user?.role == AppRole.clinico && user?.staffId != null)
            ? repo.listPatientsForStaff(user!.staffId!)
            : repo.listAllPatients();

    // Solo mostramos pacientes con internamiento activo o con alguna alerta.
    final entries = <_RiskEntry>[];
    for (final p in basePatients) {
      final risk = repo.computeRisk(p.id, catalog);
      final adm = repo.activeAdmission(p.id);
      if (risk.hasAlerts || adm != null) {
        entries.add(_RiskEntry(p, risk, adm));
      }
    }
    // Orden: mayor nivel de riesgo primero, luego por nº de alertas y nombre.
    int levelRank(RiskLevel l) => switch (l) {
          RiskLevel.alto => 0,
          RiskLevel.medio => 1,
          RiskLevel.bajo => 2,
          RiskLevel.sinRiesgo => 3,
        };
    entries.sort((a, b) {
      final r = levelRank(a.risk.level).compareTo(levelRank(b.risk.level));
      if (r != 0) return r;
      final c = b.risk.alerts.length.compareTo(a.risk.alerts.length);
      return c != 0 ? c : a.patient.fullName.compareTo(b.patient.fullName);
    });

    // Unidades disponibles (de internamientos activos) para el filtro.
    final units = entries
        .map((e) => e.admission?.unit)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    final filtered = _unitFilter == null
        ? entries
        : entries.where((e) => e.admission?.unit == _unitFilter).toList();

    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Sin pacientes con alertas de riesgo o internamiento activo.\n'
            'Registra valoraciones de Braden e internamientos para poblar el '
            'tablero.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CountsHeader(entries: entries),
        if (units.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: const Text('Todas'),
                    selected: _unitFilter == null,
                    onSelected: (_) => setState(() => _unitFilter = null),
                  ),
                ),
                for (final u in units)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(u),
                      selected: _unitFilter == u,
                      onSelected: (_) => setState(() => _unitFilter = u),
                    ),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: filtered.length,
            itemBuilder: (context, i) => _RiskBoardTile(entry: filtered[i]),
          ),
        ),
      ],
    );
  }
}

class _CountsHeader extends StatelessWidget {
  final List<_RiskEntry> entries;
  const _CountsHeader({required this.entries});

  @override
  Widget build(BuildContext context) {
    int count(RiskLevel l) => entries.where((e) => e.risk.level == l).length;
    Widget chip(String label, int n, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$label: $n',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip('Alto', count(RiskLevel.alto), KuraColors.danger),
          chip('Medio', count(RiskLevel.medio), KuraColors.warning),
          chip('Bajo', count(RiskLevel.bajo), KuraColors.success),
        ],
      ),
    );
  }
}

class _RiskBoardTile extends StatelessWidget {
  final _RiskEntry entry;
  const _RiskBoardTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = riskLevelColor(entry.risk.level);
    final adm = entry.admission;
    final n = entry.risk.alerts.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.go('/patients/${entry.patient.id}/risk'),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.16),
          child: Icon(Icons.shield_outlined, color: color, size: 20),
        ),
        title: Text(entry.patient.fullName,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [
            entry.risk.level.label,
            if (n > 0) '$n alerta${n == 1 ? '' : 's'}',
            if (adm?.unit != null) adm!.unit!,
            if (adm?.bed != null) 'Cama ${adm!.bed}',
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}
