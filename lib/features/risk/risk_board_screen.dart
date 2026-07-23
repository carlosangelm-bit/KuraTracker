import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../engine/risk/prevention_risk_engine.dart';
import '../../models/app_user.dart';
import '../../models/center_type.dart';
import '../../models/patient.dart';
import '../../models/patient_admission.dart';
import '../../services/data_repository.dart';
import 'risk_theme.dart';

/// Una entrada del tablero: paciente + su riesgo computado + internamiento +
/// (prevención hospitalaria) banda Braden, % de cumplimiento y si tiene tareas
/// vencidas.
class _RiskEntry {
  final Patient patient;
  final PreventionRiskResult risk;
  final PatientAdmission? admission;
  final int? bradenScore; // null = sin valoración
  final int compliancePct; // -1 = sin plan/actividades esperadas
  final bool overdue;
  const _RiskEntry(
    this.patient,
    this.risk,
    this.admission, {
    this.bradenScore,
    this.compliancePct = -1,
    this.overdue = false,
  });
}

/// Nivel (color) derivado de la banda de Braden: ≤12 alto (rojo), 13–17 medio
/// (ámbar), 18–23 bajo (verde). null = sin valoración (gris).
RiskLevel? bradenBandLevel(int? braden) {
  if (braden == null) return null;
  if (braden <= 12) return RiskLevel.alto;
  if (braden <= 17) return RiskLevel.medio;
  return RiskLevel.bajo;
}

/// Nivel EFECTIVO de una entrada del tablero: la banda de Braden si existe
/// (color del panel), si no el nivel de las reglas; null = sin valoración.
RiskLevel? _effectiveLevel(_RiskEntry e) =>
    bradenBandLevel(e.bradenScore) ?? (e.risk.hasAlerts ? e.risk.level : null);

/// Clave estable del nivel para el filtro ('alto'/'medio'/'bajo'/'sin').
String _levelKey(RiskLevel? l) => switch (l) {
      RiskLevel.alto => 'alto',
      RiskLevel.medio => 'medio',
      RiskLevel.bajo => 'bajo',
      _ => 'sin',
    };

/// Tablero de riesgo (módulo de Prevención): lista de pacientes con alertas
/// preventivas o internados, priorizada por nivel de riesgo y filtrable por
/// nivel de riesgo, piso y área. Capa DOCUMENTAL de apoyo a la decisión.
class RiskBoardScreen extends ConsumerStatefulWidget {
  const RiskBoardScreen({super.key});

  @override
  ConsumerState<RiskBoardScreen> createState() => _RiskBoardScreenState();
}

class _RiskBoardScreenState extends ConsumerState<RiskBoardScreen> {
  String? _levelFilter; // nivel de riesgo ('alto'/'medio'/'bajo'/'sin'), null = todos
  String? _floorFilter; // piso, null = todos
  String? _areaFilter; // área, null = todas

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final rulesAsync = ref.watch(preventionRulesProvider);
    final user = ref.watch(sessionProvider).user;
    final isHospital = repoAsync.valueOrNull?.centerTypeFor(user?.organizationId) ==
        CenterType.hospital;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prevención'),
        actions: [
          if (isHospital)
            IconButton(
              tooltip: 'Dashboard del centro',
              icon: const Icon(Icons.insights_outlined),
              onPressed: () => context.go('/hospital'),
            ),
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
    // Base de pacientes: clínico ve los suyos; los demás (admin/enfermería) ven
    // los del CENTRO ACTIVO. El filtro por organización es coherente con la
    // agenda de prevención (que ya se acota por org) y refleja el aislamiento
    // que en producción impone la RLS: un paciente de otro centro no debe
    // aparecer aquí (en demo, sin RLS, listAllPatients mostraba todos).
    final basePatients =
        (user?.role == AppRole.clinico && user?.staffId != null)
            ? repo.listPatientsForStaff(user!.staffId!)
            : repo
                .listAllPatients()
                .where((p) => p.organizationId == user?.organizationId)
                .toList();

    // Solo mostramos pacientes con internamiento activo o con alguna alerta.
    final now = DateTime.now();
    final entries = <_RiskEntry>[];
    for (final p in basePatients) {
      final risk = repo.computeRisk(p.id, catalog);
      final adm = repo.activeAdmission(p.id);
      if (risk.hasAlerts || adm != null) {
        final braden = repo.latestRiskAssessment(p.id)?.bradenScore;
        final comp = repo.preventiveCompliance(p.id,
            organizationId: user?.organizationId, now: now);
        final overdue = repo
            .listPreventiveTasks(patientId: p.id)
            .any((t) => t.isPending && t.scheduledAt.isBefore(now));
        entries.add(_RiskEntry(p, risk, adm,
            bradenScore: braden,
            compliancePct: comp.hasExpected ? comp.globalPct : -1,
            overdue: overdue));
      }
    }
    // Orden: mayor nivel primero. Usa la banda de Braden si existe (color del
    // panel), si no el nivel de las reglas. "Sin valoración" (gris) va al final.
    int rank(_RiskEntry e) {
      return switch (_effectiveLevel(e)) {
        RiskLevel.alto => 0,
        RiskLevel.medio => 1,
        RiskLevel.bajo => 2,
        _ => 3, // sin valoración / sin riesgo
      };
    }
    entries.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return a.patient.fullName.compareTo(b.patient.fullName);
    });

    // Pisos y áreas disponibles (de internamientos activos) para filtrar.
    final floors = entries
        .map((e) => e.admission?.floor)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final areas = entries
        .map((e) => e.admission?.area)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    // Conjunto acotado por ubicación (piso/área): base de las cuentas por nivel
    // (cada chip de nivel muestra cuántos coincidirían con la ubicación actual).
    final byLocation = entries
        .where((e) =>
            (_floorFilter == null || e.admission?.floor == _floorFilter) &&
            (_areaFilter == null || e.admission?.area == _areaFilter))
        .toList();
    // Encima, el filtro por nivel de riesgo.
    final filtered = byLocation
        .where((e) =>
            _levelFilter == null || _levelKey(_effectiveLevel(e)) == _levelFilter)
        .toList();

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
        _CountsHeader(
          entries: byLocation,
          selected: _levelFilter,
          onSelected: (k) => setState(() => _levelFilter = k),
        ),
        if (floors.isNotEmpty)
          _FilterChipRow(
            prefix: 'Piso',
            options: floors,
            selected: _floorFilter,
            onSelected: (v) => setState(() => _floorFilter = v),
          ),
        if (areas.isNotEmpty)
          _FilterChipRow(
            prefix: 'Área',
            options: areas,
            selected: _areaFilter,
            onSelected: (v) => setState(() => _areaFilter = v),
          ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Ningún paciente coincide con los filtros seleccionados.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : LayoutBuilder(
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
    // Color por banda de Braden (prevención hospitalaria); si no hay Braden,
    // por nivel de reglas; si no hay nada, gris "Sin valoración".
    final band = bradenBandLevel(entry.bradenScore);
    final effLevel = band ?? (entry.risk.hasAlerts ? entry.risk.level : null);
    final color = effLevel != null ? riskLevelColor(effLevel) : Colors.grey;
    final levelLabel = effLevel?.label ?? 'Sin valoración';
    final adm = entry.admission;
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
                    child: Text(levelLabel,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ),
                  const SizedBox(width: 6),
                  if (entry.overdue)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: KuraColors.danger.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Vencidas',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: KuraColors.danger)),
                    ),
                  const Spacer(),
                  if (entry.compliancePct >= 0)
                    Text('${entry.compliancePct}%',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _complianceColor(entry.compliancePct))),
                ],
              ),
              if ((adm?.locationLabel ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.local_hotel_outlined,
                        size: 14, color: KuraColors.darkText.withOpacity(0.5)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        adm!.locationLabel,
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

/// Cuentas por nivel de riesgo que además ACTÚAN como filtro: tocar un chip
/// filtra el tablero por ese nivel; tocarlo de nuevo (o cualquiera activo) lo
/// limpia. [selected] = clave del nivel filtrado ('alto'/'medio'/'bajo'/'sin').
class _CountsHeader extends StatelessWidget {
  final List<_RiskEntry> entries;
  final String? selected;
  final ValueChanged<String?> onSelected;
  const _CountsHeader({
    required this.entries,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    int count(RiskLevel l) =>
        entries.where((e) => _effectiveLevel(e) == l).length;
    final sinVal = entries.where((e) => _effectiveLevel(e) == null).length;
    Widget chip(String label, int n, Color color, String key) {
      final isSelected = selected == key;
      // Deshabilita el chip vacío salvo que esté seleccionado (para poder
      // limpiarlo si un cambio de piso/área lo dejó en cero).
      final enabled = n > 0 || isSelected;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: enabled ? () => onSelected(isSelected ? null : key) : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(isSelected ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? color : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    Icon(Icons.check, size: 13, color: color),
                    const SizedBox(width: 4),
                  ],
                  Text('$label: $n',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip('Alto', count(RiskLevel.alto), KuraColors.danger, 'alto'),
          chip('Medio', count(RiskLevel.medio), KuraColors.warning, 'medio'),
          chip('Bajo', count(RiskLevel.bajo), KuraColors.success, 'bajo'),
          if (sinVal > 0 || selected == 'sin')
            chip('Sin valoración', sinVal, Colors.grey, 'sin'),
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
    final band = bradenBandLevel(entry.bradenScore);
    final effLevel = band ?? (entry.risk.hasAlerts ? entry.risk.level : null);
    final color = effLevel != null ? riskLevelColor(effLevel) : Colors.grey;
    final levelLabel = effLevel?.label ?? 'Sin valoración';
    final adm = entry.admission;
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
            levelLabel,
            if (entry.overdue) 'Vencidas',
            if ((adm?.locationLabel ?? '').isNotEmpty) adm!.locationLabel,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: entry.compliancePct >= 0
            ? Text('${entry.compliancePct}%',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _complianceColor(entry.compliancePct)))
            : const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}

/// Color del % de cumplimiento: <60 rojo, 60–84 ámbar, ≥85 verde.
Color _complianceColor(int pct) {
  if (pct >= 85) return KuraColors.success;
  if (pct >= 60) return KuraColors.warning;
  return KuraColors.danger;
}

/// Fila de chips de filtro (piso / área) para el panel.
class _FilterChipRow extends StatelessWidget {
  final String prefix;
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;
  const _FilterChipRow({
    required this.prefix,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text('$prefix: todos'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text('$prefix $o'),
                selected: selected == o,
                onSelected: (_) => onSelected(o),
              ),
            ),
        ],
      ),
    );
  }
}
