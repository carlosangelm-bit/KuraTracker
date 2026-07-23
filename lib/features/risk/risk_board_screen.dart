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
        actions: [
          IconButton(
            tooltip: 'Agenda de tareas preventivas',
            icon: const Icon(Icons.checklist_outlined),
            onPressed: () => context.go('/prevention-agenda'),
          ),
          const UserMenuButton(),
        ],
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
          child: LayoutBuilder(
            builder: (context, c) {
              // Desktop: panel de tarjetas (todos los pacientes de un vistazo).
              // Móvil: lista compacta.
              if (c.maxWidth >= 900) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final e in filtered)
                        SizedBox(width: 340, child: _RiskCardWide(entry: e)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: filtered.length,
                itemBuilder: (context, i) => _RiskBoardTile(entry: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de paciente en el panel desktop: resumen relevante + la principal
/// acción sugerida. Al abrir muestra la guía completa (ficha de riesgo).
class _RiskCardWide extends StatelessWidget {
  final _RiskEntry entry;
  const _RiskCardWide({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = riskLevelColor(entry.risk.level);
    final adm = entry.admission;
    final n = entry.risk.alerts.length;
    // Alerta de mayor severidad = preocupación principal.
    final sorted = [...entry.risk.alerts]
      ..sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
    final top = sorted.isEmpty ? null : sorted.first;
    final topAction =
        (top != null && top.actions.isNotEmpty) ? top.actions.first.label : null;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/patients/${entry.patient.id}/risk'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: color.withOpacity(0.16),
                    child: Icon(Icons.shield_outlined, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(entry.patient.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(entry.risk.level.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ),
                  const Spacer(),
                  if (n > 0)
                    Text('$n alerta${n == 1 ? '' : 's'}',
                        style: TextStyle(
                            fontSize: 12,
                            color: KuraColors.darkText.withOpacity(0.6))),
                ],
              ),
              if (adm?.unit != null || adm?.bed != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.local_hotel_outlined,
                        size: 14, color: KuraColors.darkText.withOpacity(0.5)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        [
                          if (adm?.unit != null) adm!.unit!,
                          if (adm?.bed != null) 'Cama ${adm!.bed}',
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 12,
                            color: KuraColors.darkText.withOpacity(0.6)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (top != null) ...[
                const Divider(height: 18),
                Text(top.message,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (topAction != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_right_alt,
                          size: 16, color: KuraColors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(topAction,
                            style: const TextStyle(
                                fontSize: 12, color: KuraColors.primary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Ver guía  ›',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: KuraColors.primary)),
              ),
            ],
          ),
        ),
      ),
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
