import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../models/antecedentes.dart';
import '../../models/patient_diagnosis.dart';
import '../risk/risk_theme.dart';
import '../../models/patient.dart';
import '../../models/wound.dart';
import '../../models/consultation.dart';
import '../../models/consent.dart';
import '../../services/data_repository.dart';
import '../follow_up/follow_up_screen.dart';
import '../adverse_events/adverse_events_screen.dart' show adverseSeverityColor;
import 'cie10_picker_sheet.dart' show diagnosisRelationColor;

class PatientDetailScreen extends ConsumerStatefulWidget {
  final String patientId;
  const PatientDetailScreen({super.key, required this.patientId});

  @override
  ConsumerState<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  final _dateFmt = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final patient = repo.getPatient(widget.patientId);
          if (patient == null) {
            return const Center(child: Text('Paciente no encontrado.'));
          }
          final wounds = repo.listWoundsForPatient(patient.id);
          final consultations = repo.listConsultationsForPatient(patient.id);
          final comorbidities = repo.listComorbidities(patient.id);
          final diagnoses = repo.listDiagnoses(patient.id);
          // Si el paciente tiene UNA sola herida activa, el seguimiento se
          // muestra embebido aquí mismo (menos clicks): no hace falta entrar a
          // la pantalla de seguimiento.
          final activeWounds = wounds.where((w) => w.isActive).toList();
          final singleActiveWound = activeWounds.length == 1 ? activeWounds.first : null;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Volver a pacientes',
                  onPressed: () => context.go('/patients'),
                ),
                title: Text(patient.fullName),
                pinned: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Editar / completar expediente',
                    onPressed: () =>
                        context.go('/patients/${patient.id}/edit'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Nueva consulta',
                    onPressed: () =>
                        context.go('/patients/${patient.id}/consultation/new'),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _PatientHeaderCard(patient: patient, dateFmt: _dateFmt),
                    const SizedBox(height: 16),
                    _ComorbidityCard(
                        patientId: patient.id, comorbidities: comorbidities),
                    const SizedBox(height: 16),
                    _DiagnosesCard(patientId: patient.id, diagnoses: diagnoses),
                    const SizedBox(height: 16),
                    _RiskCard(patientId: patient.id),
                    const SizedBox(height: 16),
                    _ConsentsSummaryCard(patientId: patient.id, repo: repo),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text('Heridas',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Registrar herida'),
                          onPressed: () =>
                              context.go('/patients/${patient.id}/consultation/new'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (wounds.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Sin heridas registradas.'),
                      )
                    else
                      ...wounds.map((w) => _WoundCard(
                            patientId: patient.id,
                            wound: w,
                            repo: repo,
                            // Oculta el botón "Seguimiento" de la herida única
                            // activa: su seguimiento se muestra embebido abajo.
                            showFollowUpButton:
                                singleActiveWound == null || w.id != singleActiveWound.id,
                          )),
                    // Seguimiento EMBEBIDO cuando hay una sola herida activa.
                    if (singleActiveWound != null) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Seguimiento de la herida',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text('Registrar seguimiento'),
                            onPressed: () => context.go(
                                '/patients/${patient.id}/wound/${singleActiveWound.id}/follow-up/new'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FollowUpBody(
                        patientId: patient.id,
                        woundId: singleActiveWound.id,
                        embedded: true,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('Historial de consultas',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    if (consultations.isEmpty)
                      const Text('Sin consultas registradas.')
                    else
                      ...consultations.map((c) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () => context
                                  .go('/patients/${widget.patientId}/consultation/${c.id}'),
                              leading: Icon(
                                c.visitType == VisitType.valoracion
                                    ? Icons.assignment_outlined
                                    : Icons.update,
                                color: KuraColors.primary,
                              ),
                              title: Text(c.visitType.label),
                              subtitle: Text(_dateFmt.format(c.visitDate)),
                              trailing: c.isDraft
                                  ? const Chip(
                                      label: Text('Borrador'),
                                      backgroundColor: KuraColors.chipBg,
                                    )
                                  : const Icon(Icons.chevron_right, size: 18),
                            ),
                          )),
                    const SizedBox(height: 24),
                    _AdverseEventsSection(patientId: patient.id, repo: repo),
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        onTap: () =>
                            context.go('/patients/${patient.id}/referrals'),
                        leading: const Icon(Icons.forward_to_inbox_outlined,
                            color: KuraColors.primary),
                        title: const Text('Referencias / interconsultas'),
                        subtitle: Text(
                          () {
                            final refs =
                                repo.listReferralsForPatient(patient.id);
                            final pend = refs
                                .where((r) => !r.isRespondida)
                                .length;
                            if (refs.isEmpty) return 'Generar formato de referencia';
                            return '${refs.length} referencia(s)'
                                '${pend > 0 ? ' · $pend pendiente(s) de respuesta' : ''}';
                          }(),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PatientHeaderCard extends StatelessWidget {
  final Patient patient;
  final DateFormat dateFmt;
  const _PatientHeaderCard({required this.patient, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(patient.folio),
                  backgroundColor: KuraColors.primary.withOpacity(0.1),
                  labelStyle: const TextStyle(
                      color: KuraColors.primary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                if (patient.fragilePatient)
                  const Chip(
                    label: Text('Frágil'),
                    backgroundColor: Color(0x1AE8A93A),
                    avatar: Icon(Icons.priority_high, size: 16, color: KuraColors.warning),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _InfoItem(label: 'Edad', value: '${patient.age ?? '-'} años'),
                _InfoItem(label: 'Sexo', value: patient.sex ?? '-'),
                _InfoItem(
                  label: 'Movilidad',
                  value: patient.mobility ?? '-',
                ),
                _InfoItem(
                  label: 'Cuidador',
                  value: patient.hasIdentifiedCaregiver
                      ? (patient.caregiverName ?? 'Identificado')
                      : 'No identificado',
                ),
                if (patient.curp != null && patient.curp!.isNotEmpty)
                  _InfoItem(label: 'CURP', value: patient.curp!),
                if (patient.occupation != null && patient.occupation!.isNotEmpty)
                  _InfoItem(label: 'Ocupación', value: patient.occupation!),
                if (patient.weightKg != null || patient.heightCm != null)
                  _InfoItem(
                    label: 'Peso / Talla',
                    value:
                        '${patient.weightKg != null ? '${patient.weightKg} kg' : '-'} / '
                        '${patient.heightCm != null ? '${patient.heightCm} cm' : '-'}'
                        '${patient.bmi != null ? '  ·  IMC ${patient.bmi!.toStringAsFixed(1)}' : ''}',
                  ),
                if (patient.responsibleName != null &&
                    patient.responsibleName!.isNotEmpty)
                  _InfoItem(
                    label: 'Responsable',
                    value:
                        '${patient.responsibleName!}${patient.responsibleRelationship != null && patient.responsibleRelationship!.isNotEmpty ? ' (${patient.responsibleRelationship})' : ''}',
                  ),
                if (patient.ekareExternalId != null)
                  _InfoItem(label: 'eKare ID', value: patient.ekareExternalId!),
              ],
            ),
            if (patient.address != null && patient.address!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InfoItem(label: 'Domicilio', value: patient.address!),
            ],
            if (patient.backgroundNotes != null && patient.backgroundNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text('Antecedentes',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KuraColors.darkText.withOpacity(0.6))),
              const SizedBox(height: 4),
              Text(patient.backgroundNotes!),
            ],
            if (patient.familyHistory.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Antecedentes heredo-familiares',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KuraColors.darkText.withOpacity(0.6))),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: patient.familyHistory
                    .map((a) => Chip(
                          label: Text(a.label, style: const TextStyle(fontSize: 12)),
                          backgroundColor: KuraColors.chipBg,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
            if (patient.smoking != null ||
                patient.alcohol != null ||
                patient.physicalActivity != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (patient.smoking != null) 'Tabaquismo: ${patient.smoking!.label}',
                  if (patient.alcohol != null) 'Alcohol: ${patient.alcohol!.label}',
                  if (patient.physicalActivity != null)
                    'Actividad: ${patient.physicalActivity!.label}',
                ].join('  ·  '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.5))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ComorbidityCard extends StatelessWidget {
  final String patientId;
  final List<PatientComorbidity> comorbidities;
  const _ComorbidityCard({required this.patientId, required this.comorbidities});

  @override
  Widget build(BuildContext context) {
    // Solo mostramos las evaluadas (presente/negado); las "no evaluado" son el
    // estado por defecto y no aportan. Presente = cuenta para el arquetipo.
    final evaluadas = comorbidities
        .where((c) => c.status != ComorbilidadEstado.noEvaluado)
        .toList();
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/patients/$patientId/comorbidities'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Comorbilidades (APP)',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              if (evaluadas.isEmpty)
                Text('Registrar antecedentes personales patológicos',
                    style: Theme.of(context).textTheme.bodySmall)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: evaluadas.map((c) {
                    final color = c.status == ComorbilidadEstado.presente
                        ? KuraColors.danger
                        : KuraColors.success;
                    return Chip(
                      label:
                          Text(c.code.label, style: const TextStyle(fontSize: 12)),
                      avatar: Icon(Icons.circle, size: 10, color: color),
                      backgroundColor: KuraColors.chipBg,
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de prevención/riesgo del expediente. Muestra el nivel de riesgo
/// computado y el nº de alertas; navega a la ficha de riesgo. Capa DOCUMENTAL.
class _RiskCard extends ConsumerWidget {
  final String patientId;
  const _RiskCard({required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;
    final rules = ref.watch(preventionRulesProvider).valueOrNull;
    PreventionRiskResult? result;
    if (repo != null && rules != null) {
      result = repo.computeRisk(patientId, rules);
    }
    final level = result?.level ?? RiskLevel.sinRiesgo;
    final color = riskLevelColor(level);
    final n = result?.alerts.length ?? 0;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/patients/$patientId/risk'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Prevención y riesgo',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      result == null
                          ? 'Ver alertas preventivas'
                          : '${level.label}${n > 0 ? ' · $n alerta${n == 1 ? '' : 's'}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: result != null && level != RiskLevel.sinRiesgo
                              ? color
                              : null),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de diagnósticos CIE-10 del expediente (NOM-004). Muestra el conteo
/// activo y el diagnóstico principal; navega a la pantalla de gestión. Registro
/// documental: no toca el motor Kura+ (eso es la tarjeta de comorbilidades).
class _DiagnosesCard extends StatelessWidget {
  final String patientId;
  final List<PatientDiagnosis> diagnoses;
  const _DiagnosesCard({required this.patientId, required this.diagnoses});

  @override
  Widget build(BuildContext context) {
    final activos =
        diagnoses.where((d) => d.status == DiagnosisStatus.activo).toList();
    PatientDiagnosis? principal;
    for (final d in activos) {
      if (d.isPrimary) {
        principal = d;
        break;
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/patients/$patientId/diagnoses'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Diagnósticos (CIE-10)'
                      '${activos.isEmpty ? '' : ' · ${activos.length}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              if (activos.isEmpty)
                Text('Registrar diagnóstico codificado del expediente',
                    style: Theme.of(context).textTheme.bodySmall)
              else ...[
                if (principal != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.star,
                            size: 14, color: KuraColors.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('${principal.code} · ${principal.name}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: activos
                      .where((d) => !d.isPrimary)
                      .take(6)
                      .map((d) => Chip(
                            label: Text(d.code,
                                style: const TextStyle(fontSize: 12)),
                            avatar: Icon(Icons.circle,
                                size: 10,
                                color: diagnosisRelationColor(d.relation)),
                            backgroundColor: KuraColors.chipBg,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WoundCard extends StatelessWidget {
  final String patientId;
  final Wound wound;
  final DataRepository repo;
  // Se oculta cuando el seguimiento ya se muestra EMBEBIDO abajo (paciente con
  // una sola herida activa) — el botón navegaría a la misma información.
  final bool showFollowUpButton;
  const _WoundCard({
    required this.patientId,
    required this.wound,
    required this.repo,
    this.showFollowUpButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final measurements = repo.listMeasurementsForWound(wound.id);
    final latest = measurements.isNotEmpty ? measurements.last : null;
    final recs = repo.listRecommendationsForWound(wound.id);
    final lastRec = recs.isNotEmpty ? recs.last : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: KuraColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.healing, color: KuraColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(wound.etiology.label,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (wound.subtype != null)
                        Text(wound.subtype!, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                if (lastRec != null)
                  _ScenarioBadge(scenario: lastRec['dominant_scenario'] as String),
              ],
            ),
            if (latest != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _MiniStat(label: 'Área', value: '${latest.areaCm2.toStringAsFixed(1)} cm²'),
                  _MiniStat(label: 'Profundidad', value: '${latest.depthCm} cm'),
                  _MiniStat(
                      label: 'Necrosis+Esfacelo',
                      value:
                          '${(latest.necrosisPct + latest.sloughPct).toStringAsFixed(0)}%'),
                ],
              ),
            ],
            const SizedBox(height: 10),
            // Wrap (no Row): en telefonos angostos los dos botones etiquetados
            // se reacomodan a otra linea en vez de desbordar horizontalmente.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                // Wrap (responsive) + botón condicional: se oculta "Seguimiento"
                // cuando el seguimiento ya se muestra embebido abajo (1 herida).
                if (showFollowUpButton)
                  TextButton.icon(
                    icon: const Icon(Icons.show_chart, size: 18),
                    label: const Text('Seguimiento'),
                    onPressed: () =>
                        context.go('/patients/$patientId/wound/${wound.id}/follow-up'),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Nueva valoración'),
                  onPressed: () =>
                      context.go('/patients/$patientId/wound/${wound.id}/capture'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: KuraColors.darkText),
        children: [
          TextSpan(text: '$label: ', style: TextStyle(color: KuraColors.darkText.withOpacity(0.5))),
          TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ScenarioBadge extends StatelessWidget {
  final String scenario;
  const _ScenarioBadge({required this.scenario});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (scenario) {
      case 'A':
        color = KuraColors.scenarioA;
        break;
      case 'B':
        color = KuraColors.scenarioB;
        break;
      default:
        color = KuraColors.scenarioC;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('Escenario $scenario',
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// Sección "Eventos adversos" en el detalle del paciente: cabecera + acción de
/// registro, marca de alerta de eventos centinela pendientes de reporte, y
/// acceso a la bitácora completa. Ver módulo lib/features/adverse_events/.
class _AdverseEventsSection extends StatelessWidget {
  final String patientId;
  final DataRepository repo;
  const _AdverseEventsSection({required this.patientId, required this.repo});

  @override
  Widget build(BuildContext context) {
    final events = repo.listAdverseEventsForPatient(patientId);
    final pendientes = events.where((e) => e.needsReport).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Eventos adversos',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Registrar evento'),
              onPressed: () =>
                  context.go('/patients/$patientId/adverse-events/new'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (pendientes > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KuraColors.danger.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: KuraColors.danger.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: KuraColors.danger, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pendientes == 1
                        ? '1 evento centinela pendiente de reporte (≤24 h).'
                        : '$pendientes eventos centinela pendientes de reporte (≤24 h).',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: KuraColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        if (events.isEmpty)
          const Text('Sin eventos adversos registrados.')
        else
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              onTap: () => context.go('/patients/$patientId/adverse-events'),
              leading: Icon(
                Icons.report_problem_outlined,
                color: adverseSeverityColor(events.first.severity),
              ),
              title: Text('Bitácora de eventos (${events.length})'),
              subtitle: Text('Más reciente: ${events.first.type}'),
              trailing: const Icon(Icons.chevron_right, size: 18),
            ),
          ),
      ],
    );
  }
}

/// Tarjeta-resumen de consentimientos del paciente (Protocolos "Expedientes
/// clínicos" y "Desbridamiento"): estado por tipo + acceso a la gestión.
class _ConsentsSummaryCard extends StatelessWidget {
  final String patientId;
  final DataRepository repo;
  const _ConsentsSummaryCard({required this.patientId, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/patients/$patientId/consents'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.assignment_turned_in_outlined,
                      color: KuraColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Consentimientos',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ConsentType.values.map((type) {
                  final granted = repo.hasConsent(patientId, type);
                  final color =
                      granted ? KuraColors.success : KuraColors.danger;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          granted ? Icons.check_circle : Icons.cancel_outlined,
                          size: 14,
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        Text(type.label,
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
