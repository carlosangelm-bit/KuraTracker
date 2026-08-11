import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/commercial.dart';
import '../../models/consultation.dart';
import '../../models/note_option_catalog.dart';
import '../../models/protocol_product_rule.dart';
import '../../models/consultation_supply_usage.dart';
import '../../models/inventory.dart';
import '../../models/supply_product_mapping.dart';
import '../../models/treatment_plan.dart';
import '../../models/wound.dart';
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';

/// Detalle de consulta, de SOLO LECTURA, como referencia historica.
///
/// Muestra todo lo registrado en una consulta especifica: datos generales,
/// la(s) herida(s) evaluadas en esa consulta y su evaluacion (mediciones,
/// composicion del lecho, exudado, infeccion, borde, perilesional), la
/// recomendacion Kura+ emitida si la hubo, el tratamiento aplicado y las
/// fotos tomadas en esa consulta.
///
/// No existen metodos en DataRepository para filtrar directamente por
/// consultation_id en measurements/assessments/photos/kura_recommendations
/// (la mayoria filtran por wound_id); en vez de agregar nuevos metodos al
/// repositorio, se filtran aqui client-side las listas ya expuestas por
/// wound_id — es la misma cache en memoria hidratada por RLS, no una
/// consulta adicional al backend. RLS ya garantiza que un clinico solo vea
/// las consultas/heridas/mediciones que tiene asignadas.
class ConsultationDetailScreen extends ConsumerWidget {
  final String patientId;
  final String consultationId;
  const ConsultationDetailScreen({
    super.key,
    required this.patientId,
    required this.consultationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final dateFmt = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver al paciente',
          onPressed: () => context.go('/patients/$patientId'),
        ),
        title: const Text('Detalle de consulta'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final consultation = repo.getConsultation(consultationId);
          if (consultation == null) {
            return const Center(child: Text('Consulta no encontrada.'));
          }
          final patient = repo.getPatient(patientId);
          final site = repo.listSites().where((s) => s.id == consultation.siteId);
          final staff = repo.listStaff().where((s) => s.id == consultation.staffId);

          // Heridas vinculadas a esta consulta: se infieren de las
          // mediciones/evaluaciones que traen ese consultation_id, ya que
          // `wounds` no tiene FK directa a consultations (una herida puede
          // tener multiples consultas a lo largo del tiempo).
          final wounds = repo.listWoundsForPatient(patientId);
          final woundIdsInConsultation = <String>{};
          final measurementsByWound = <String, WoundMeasurement>{};
          final assessmentsByWound = <String, WoundAssessment>{};
          for (final w in wounds) {
            final measurement = repo
                .listMeasurementsForWound(w.id)
                .where((m) => m.consultationId == consultationId);
            final assessment = repo
                .listAssessmentsForWound(w.id)
                .where((a) => a.consultationId == consultationId);
            if (measurement.isNotEmpty || assessment.isNotEmpty) {
              woundIdsInConsultation.add(w.id);
              if (measurement.isNotEmpty) measurementsByWound[w.id] = measurement.first;
              if (assessment.isNotEmpty) assessmentsByWound[w.id] = assessment.first;
            }
          }
          final woundsInConsultation =
              wounds.where((w) => woundIdsInConsultation.contains(w.id)).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GeneralDataCard(
                  consultation: consultation,
                  patientName: patient?.fullName,
                  siteName: site.isNotEmpty ? site.first.name : null,
                  staffName: staff.isNotEmpty ? staff.first.fullName : null,
                  dateFmt: dateFmt,
                ),
                const SizedBox(height: 16),
                // Borrador (valoración o seguimiento): retomar el formulario
                // para continuarlo, o descartarlo. Antes solo el seguimiento
                // podía retomarse, así que un borrador de valoración quedaba
                // atascado (ni continuar ni borrar).
                if (consultation.isDraft) ...[
                  Builder(builder: (ctx) {
                    final isFollowUp =
                        consultation.visitType == VisitType.seguimiento;
                    final woundId = isFollowUp
                        ? repo.woundIdForConsultation(consultationId)
                        : null;
                    final canContinue = !isFollowUp || woundId != null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Continuar consulta (borrador)'),
                          onPressed: !canContinue
                              ? null
                              : () => context.go(isFollowUp
                                  ? '/patients/$patientId/wound/$woundId/follow-up/draft/$consultationId'
                                  : '/patients/$patientId/wound/new/capture?consultationId=$consultationId'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline,
                              color: KuraColors.danger),
                          label: const Text('Eliminar borrador',
                              style: TextStyle(color: KuraColors.danger)),
                          onPressed: () => _confirmDeleteDraft(
                              context, repo, patientId, consultationId),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                ],
                if (woundsInConsultation.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Esta consulta no tiene evaluación ni medición de herida asociada '
                        '(pudo ser una interconsulta o un encabezado sin captura completa).',
                      ),
                    ),
                  )
                else
                  ...woundsInConsultation.map((wound) => _WoundSection(
                        wound: wound,
                        measurement: measurementsByWound[wound.id],
                        assessment: assessmentsByWound[wound.id],
                        repo: repo,
                        consultationId: consultationId,
                        dateFmt: dateFmt,
                      )),
                const SizedBox(height: 16),
                _SuppliesUsedSection(
                  consultationId: consultationId,
                  patientId: patientId,
                  organizationId: patient?.organizationId,
                  siteId: consultation.siteId,
                ),
                const SizedBox(height: 16),
                _NotesSummaryCard(
                  consultation: consultation,
                  isAdmin: ref.watch(sessionProvider).user?.role ==
                          AppRole.admin ||
                      ref.watch(sessionProvider).user?.role == AppRole.master,
                ),
                const SizedBox(height: 16),
                _AmendmentsSection(
                  patientId: patientId,
                  consultationId: consultationId,
                  dateFmt: dateFmt,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Confirma y elimina un borrador de consulta (+ su captura de herida), luego
/// regresa al expediente del paciente.
Future<void> _confirmDeleteDraft(
  BuildContext context,
  DataRepository repo,
  String patientId,
  String consultationId,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminar borrador'),
      content: const Text(
          'Se eliminará este borrador de consulta y la captura asociada '
          '(fotos/medición). Esta acción no se puede deshacer.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KuraColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await repo.deleteConsultation(consultationId);
  if (context.mounted) context.go('/patients/$patientId');
}

/// Notas del especialista + resumen (Plaud) + transcripción. La transcripción
/// solo la ve el admin/master del centro (privacidad, 0069).
class _NotesSummaryCard extends StatelessWidget {
  final Consultation consultation;
  final bool isAdmin;
  const _NotesSummaryCard({required this.consultation, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final notes = (consultation.specialistNotes ?? '').trim();
    final summary = (consultation.visitSummary ?? '').trim();
    final transcript = (consultation.transcript ?? '').trim();
    final showTranscript = isAdmin && transcript.isNotEmpty;
    if (notes.isEmpty && summary.isEmpty && !showTranscript) {
      return const SizedBox.shrink();
    }
    Widget block(String title, String body, {IconData? icon}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: KuraColors.primary),
                const SizedBox(width: 6),
              ],
              Text(title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(body),
            const SizedBox(height: 12),
          ],
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notas y resumen',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (notes.isNotEmpty) block('Notas del especialista', notes),
            if (summary.isNotEmpty)
              block('Resumen de la consulta', summary,
                  icon: Icons.auto_awesome),
            if (showTranscript)
              block('Transcripción completa (solo admin)', transcript,
                  icon: Icons.lock_outline),
          ],
        ),
      ),
    );
  }
}

class _GeneralDataCard extends StatelessWidget {
  final Consultation consultation;
  final String? patientName;
  final String? siteName;
  final String? staffName;
  final DateFormat dateFmt;
  const _GeneralDataCard({
    required this.consultation,
    required this.patientName,
    required this.siteName,
    required this.staffName,
    required this.dateFmt,
  });

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
                  label: Text(consultation.visitType.label),
                  backgroundColor: KuraColors.primary.withOpacity(0.1),
                  labelStyle: const TextStyle(
                      color: KuraColors.primary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                if (consultation.isDraft)
                  const Chip(
                    label: Text('Borrador'),
                    backgroundColor: KuraColors.chipBg,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _InfoItem(label: 'Fecha', value: dateFmt.format(consultation.visitDate)),
                if (patientName != null) _InfoItem(label: 'Paciente', value: patientName!),
                _InfoItem(label: 'Sitio', value: siteName ?? '-'),
                _InfoItem(label: 'Personal sanitario', value: staffName ?? '-'),
              ],
            ),
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

class _WoundSection extends StatelessWidget {
  final Wound wound;
  final WoundMeasurement? measurement;
  final WoundAssessment? assessment;
  final DataRepository repo;
  final String consultationId;
  final DateFormat dateFmt;
  const _WoundSection({
    required this.wound,
    required this.measurement,
    required this.assessment,
    required this.repo,
    required this.consultationId,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    final recs = repo
        .listRecommendationsForWound(wound.id)
        .where((r) => r['consultation_id'] == consultationId);
    final recommendation = recs.isNotEmpty ? recs.first : null;

    final treatmentPlan = repo.getTreatmentPlanForConsultation(consultationId, wound.id);

    final photos = repo
        .listPhotosForWound(wound.id)
        .where((p) => p.consultationId == consultationId)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                ],
              ),
              const Divider(height: 24),
              if (measurement != null) ..._measurementSection(measurement!),
              if (assessment != null) ..._assessmentSection(assessment!),
              if (recommendation != null) ..._recommendationSection(recommendation),
              if (treatmentPlan != null) ..._treatmentSection(treatmentPlan),
              if (photos.isNotEmpty) ..._photosSection(photos),
              if (measurement == null &&
                  assessment == null &&
                  recommendation == null &&
                  treatmentPlan == null &&
                  photos.isEmpty)
                const Text('Sin datos clínicos adicionales registrados en esta consulta.'),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _measurementSection(WoundMeasurement m) => [
        _SubTitle('Mediciones'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _MiniStat(label: 'Fecha', value: dateFmt.format(m.measuredAt)),
            _MiniStat(label: 'Largo', value: '${m.lengthCm} cm'),
            _MiniStat(label: 'Ancho', value: '${m.widthCm} cm'),
            _MiniStat(label: 'Área', value: '${m.areaCm2.toStringAsFixed(1)} cm²'),
            _MiniStat(label: 'Profundidad', value: '${m.depthCm} cm'),
            // Volumen (feat/volume-kundin-charts): solo se muestra si hay
            // dato (heridas superficiales sin profundidad no lo tienen; no
            // se fuerza un valor con "N/A" fuera de contexto en el Wrap).
            if (m.volumeCm3 != null)
              _MiniStat(label: 'Volumen', value: '${m.volumeCm3!.toStringAsFixed(2)} cm³'),
            if (m.tunneling) _MiniStat(label: 'Tunelización', value: 'Sí'),
            if (m.undermining) _MiniStat(label: 'Socavamiento', value: 'Sí'),
          ],
        ),
        if (m.volumeCm3 != null && m.volumeManual) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note, size: 14, color: KuraColors.warning),
              const SizedBox(width: 4),
              Text('✎ Volumen ajustado manualmente',
                  style: TextStyle(
                      fontSize: 11, color: KuraColors.warning, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Text('Composición del lecho', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _MiniStat(label: 'Granulación', value: '${m.granulationPct.toStringAsFixed(0)}%'),
            _MiniStat(label: 'Esfacelo', value: '${m.sloughPct.toStringAsFixed(0)}%'),
            _MiniStat(label: 'Necrosis', value: '${m.necrosisPct.toStringAsFixed(0)}%'),
            _MiniStat(
                label: 'Epitelización', value: '${m.epithelializationPct.toStringAsFixed(0)}%'),
          ],
        ),
        Text(
          m.capturedBeforeDebridement
              ? 'Capturado antes de curar/desbridar'
              : 'Capturado después de curar/desbridar',
          style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.5)),
        ),
        const SizedBox(height: 16),
      ];

  List<Widget> _assessmentSection(WoundAssessment a) => [
        _SubTitle('Evaluación clínica'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            if (a.exudateAmount != ExudadoCantidad.ninguno)
              _MiniStat(label: 'Exudado (cantidad)', value: a.exudateAmount.name),
            if (a.exudateType != null)
              _MiniStat(label: 'Exudado (tipo)', value: a.exudateType!.name),
            if (a.odor != null) _MiniStat(label: 'Olor', value: a.odor!),
            if (a.woundEdge != null) _MiniStat(label: 'Borde', value: a.woundEdge!),
            if (a.painVas != null) _MiniStat(label: 'Dolor (EVA)', value: '${a.painVas}/10'),
            if (a.lowAdherence) _MiniStat(label: 'Adherencia', value: 'Baja'),
          ],
        ),
        if (a.infectionCriteria.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Criterios de infección (IWII)',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: a.infectionCriteria
                .map((c) => Chip(
                      label: Text(c.name, style: const TextStyle(fontSize: 11)),
                      backgroundColor: KuraColors.danger.withOpacity(0.1),
                    ))
                .toList(),
          ),
        ],
        if (a.perilesionalSkin.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Piel perilesional',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: a.perilesionalSkin
                .map((c) => Chip(
                      label: Text(c.name, style: const TextStyle(fontSize: 11)),
                      backgroundColor: KuraColors.chipBg,
                    ))
                .toList(),
          ),
        ],
        if (a.clinicalNotes != null && a.clinicalNotes!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Notas clínicas / Observaciones',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          Text(a.clinicalNotes!.trim(), style: const TextStyle(fontSize: 13)),
        ],
        // Exploración de miembros inferiores (vascular / pie diabético, 0087).
        ..._labeledText('ITB (índice tobillo-brazo)', a.itbTexto),
        ..._labeledText('Pruebas de sensibilidad', a.pruebasSensibilidad),
        ..._labeledText('Llenado capilar', a.llenadoCapilar),
        const SizedBox(height: 16),
      ];

  /// Renglón etiqueta + texto libre; vacío si el valor no viene.
  List<Widget> _labeledText(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 4),
      Text(value.trim(), style: const TextStyle(fontSize: 13)),
    ];
  }

  List<Widget> _recommendationSection(Map<String, dynamic> rec) {
    final scenario = rec['dominant_scenario'] as String? ?? '-';
    final phenotype = rec['commercial_phenotype'] as String?;
    final regimen = (rec['regimen'] as List?) ?? [];
    final interconsultas = (rec['interconsultas'] as List?) ?? [];
    return [
      _SubTitle('Recomendación Kura+'),
      const SizedBox(height: 8),
      Row(
        children: [
          _ScenarioBadge(scenario: scenario),
          if (phenotype != null) ...[
            const SizedBox(width: 8),
            Text(phenotype, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ],
      ),
      if (regimen.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('Régimen sugerido', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        ...regimen.map((r) {
          final map = r as Map;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• ${map['metodo']} — ${map['producto']}',
                style: const TextStyle(fontSize: 13)),
          );
        }),
      ],
      if (interconsultas.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('Interconsultas', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: interconsultas.map((i) {
            final map = i as Map;
            final urgente = map['es_urgente'] as bool? ?? false;
            return Chip(
              label: Text(map['especialidad'] as String, style: const TextStyle(fontSize: 11)),
              backgroundColor: (urgente ? KuraColors.danger : KuraColors.infoBlue)
                  .withOpacity(0.1),
            );
          }).toList(),
        ),
      ],
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _treatmentSection(TreatmentPlan plan) => [
        _SubTitle('Tratamiento aplicado'),
        const SizedBox(height: 8),
        if (plan.components.isEmpty)
          const Text('Sin componentes registrados.', style: TextStyle(fontSize: 13))
        else
          ...plan.components.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${c.method} — ${c.product}', style: const TextStyle(fontSize: 13)),
              )),
        if (plan.finalDescription != null && plan.finalDescription!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(plan.finalDescription!, style: const TextStyle(fontSize: 13)),
        ],
        const SizedBox(height: 16),
      ];

  List<Widget> _photosSection(List<WoundPhoto> photos) => [
        _SubTitle('Fotos'),
        const SizedBox(height: 8),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 110,
                height: 110,
                child: FutureBuilder<String>(
                  future: PhotoUploadService.resolveDisplayUrl(photos[i].storagePath),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    return Image.network(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          const Icon(Icons.broken_image_outlined),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ];
}

class _SubTitle extends StatelessWidget {
  final String text;
  const _SubTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: KuraColors.primary));
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

/// Sección de NOTAS DE ENMIENDA / ACLARACIÓN de la consulta (NOM-004, Fase 4).
/// Append-only: muestra las enmiendas existentes y permite agregar una nueva
/// (nunca editar/borrar el original). Cada enmienda queda firmada + fechada.
class _AmendmentsSection extends ConsumerStatefulWidget {
  final String patientId;
  final String consultationId;
  final DateFormat dateFmt;
  const _AmendmentsSection({
    required this.patientId,
    required this.consultationId,
    required this.dateFmt,
  });

  @override
  ConsumerState<_AmendmentsSection> createState() => _AmendmentsSectionState();
}

class _AmendmentsSectionState extends ConsumerState<_AmendmentsSection> {
  Future<void> _addAmendment() async {
    final result = await showDialog<_AmendmentResult>(
      context: context,
      builder: (_) => const _AddAmendmentDialog(),
    );
    if (result == null) return;
    final session = ref.read(sessionProvider);
    final repo = await DataRepository.instance();
    var staffId = session.user?.staffId;
    if (staffId == null && session.user?.role == AppRole.admin) {
      staffId = await repo.ensureAdminStaffId(session.user!);
    }
    final staff = staffId == null ? null : repo.getStaff(staffId);
    await repo.addAmendment(
      patientId: widget.patientId,
      consultationId: widget.consultationId,
      body: result.body,
      reason: result.reason,
      staffId: staffId,
      signedBy: session.user?.fullName,
      signedLicense: staff?.cedulaProfesional,
    );
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nota de enmienda agregada.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    return repoAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (repo) {
        final amendments =
            repo.listAmendmentsForConsultation(widget.consultationId);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Enmiendas / aclaraciones',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      label: const Text('Agregar aclaración'),
                      onPressed: _addAmendment,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Las notas firmadas no se editan ni se borran; las correcciones '
                  'se agregan como aclaración fechada y firmada (NOM-004).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (amendments.isEmpty)
                  Text('Sin enmiendas.',
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  ...amendments.map((a) => Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: KuraColors.chipBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.dateFmt.format(a.createdAt.toLocal()),
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(a.body),
                            if ((a.reason ?? '').isNotEmpty)
                              Text('Motivo: ${a.reason}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            if ((a.signedBy ?? '').isNotEmpty)
                              Text(
                                'Firma: ${a.signedBy}'
                                '${(a.signedLicense ?? '').isNotEmpty ? ' · Céd. ${a.signedLicense}' : ''}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AmendmentResult {
  final String body;
  final String? reason;
  _AmendmentResult(this.body, this.reason);
}

class _AddAmendmentDialog extends StatefulWidget {
  const _AddAmendmentDialog();

  @override
  State<_AddAmendmentDialog> createState() => _AddAmendmentDialogState();
}

class _AddAmendmentDialogState extends State<_AddAmendmentDialog> {
  final _bodyCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nota de enmienda / aclaración'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _bodyCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Aclaración / corrección *',
              hintText: 'Qué se corrige o aclara respecto a la nota original',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final body = _bodyCtrl.text.trim();
            if (body.isEmpty) return;
            Navigator.pop(
              context,
              _AmendmentResult(
                body,
                _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Firmar y agregar'),
        ),
      ],
    );
  }
}

/// Insumos utilizados en la consulta (Fase B, premium). El profesional marca los
/// insumos usados y, por cada uno, si se COBRA y si se DESCUENTA del inventario
/// (independientes). Sugiere del plan de tratamiento vía los mapeos (Fase 2) +
/// inventario (Fase 3). El cobro/descuento real se materializa en fases C/D.
class _SuppliesUsedSection extends ConsumerStatefulWidget {
  final String consultationId;
  final String patientId;
  final String? organizationId;
  final String? siteId;
  const _SuppliesUsedSection({
    required this.consultationId,
    required this.patientId,
    required this.organizationId,
    required this.siteId,
  });

  @override
  ConsumerState<_SuppliesUsedSection> createState() =>
      _SuppliesUsedSectionState();
}

class _SuppliesUsedSectionState extends ConsumerState<_SuppliesUsedSection> {
  String _money(double v) => '\$${v.toStringAsFixed(2)} MXN';
  bool _preloadTried = false;

  @override
  void initState() {
    super.initState();
    // Pre-carga los insumos del plan mensual (por sesión) la primera vez que se
    // abre el seguimiento, si aún no hay insumos. Post-frame para no tocar
    // estado durante el build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePreload());
  }

  Future<void> _maybePreload() async {
    if (_preloadTried) return;
    _preloadTried = true;
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    final orgId = widget.organizationId;
    if (repo == null || orgId == null || !repo.premiumInsumosFor(orgId)) return;
    final n = await repo.preloadProgramSuppliesIntoConsultation(
      consultationId: widget.consultationId,
      organizationId: orgId,
      patientId: widget.patientId,
      createdBy: ref.read(sessionProvider).user?.id,
    );
    if (n > 0 && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Se pre-cargaron $n insumo(s) del plan mensual.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;
    if (repo == null) return const SizedBox.shrink();
    final orgId = widget.organizationId;
    // Solo centros con el módulo de Insumos premium.
    if (!repo.premiumInsumosFor(orgId)) return const SizedBox.shrink();

    final usage = repo.listSupplyUsageForConsultation(widget.consultationId);
    final chargeTotal = repo.consultationSuppliesChargeTotal(widget.consultationId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Insumos utilizados',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (chargeTotal > 0)
                  Text(_money(chargeTotal),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: KuraColors.primary)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Marca los insumos usados. Por cada uno elige si se cobra al paciente '
              'y si se descuenta del inventario (p. ej. algo que rinde para varias '
              'consultas no se cobra ni descuenta cada vez).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Sugerir del plan'),
                  onPressed: () => _suggestFromPlan(repo),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar insumo'),
                  onPressed: () => _addManual(repo),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (usage.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aún no se registran insumos para esta consulta.',
                    style: TextStyle(fontSize: 13)),
              )
            else
              ...usage.map((u) => _UsageRow(
                    usage: u,
                    onQty: (q) async {
                      await repo.updateSupplyUsage(u.id, quantity: q);
                      if (mounted) setState(() {});
                    },
                    onCharge: (v) async {
                      await repo.updateSupplyUsage(u.id, charge: v);
                      if (mounted) setState(() {});
                    },
                    onDiscount: (v) async {
                      await repo.updateSupplyUsage(u.id, discount: v);
                      if (mounted) setState(() {});
                    },
                    onDelete: () async {
                      await repo.deleteSupplyUsage(u.id);
                      if (mounted) setState(() {});
                    },
                  )),
            const Divider(height: 20),
            _chargeArea(repo),
          ],
        ),
      ),
    );
  }

  Widget _chargeArea(DataRepository repo) {
    // Un BORRADOR SÍ se puede cobrar: el kurador avanza al cobro aunque la
    // consulta no esté finalizada; completa lo clínico después.
    final existing = repo.chargeForConsultation(widget.consultationId);
    if (existing != null) {
      final paid = existing.status == ChargeStatus.pagado;
      return Row(
        children: [
          Expanded(
            child: Text(
              'Cobro de la consulta: ${_money(existing.total)} · ${existing.status.label}',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: paid ? KuraColors.success : KuraColors.warning),
            ),
          ),
          if (existing.status == ChargeStatus.pendiente)
            FilledButton.tonal(
              onPressed: () => _registrarPago(repo, existing),
              child: const Text('Registrar pago'),
            )
          else if (paid)
            const Icon(Icons.verified_outlined, color: KuraColors.success),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: const Icon(Icons.point_of_sale_outlined, size: 18),
        label: const Text('Cobrar consulta'),
        onPressed: () => _cobrarConsulta(repo),
      ),
    );
  }

  Future<void> _cobrarConsulta(DataRepository repo) async {
    final orgId = widget.organizationId;
    if (orgId == null) return;
    final services = repo.listServices(orgId);
    final suppliesTotal =
        repo.consultationSuppliesChargeTotal(widget.consultationId);
    ServiceCatalogItem? selected = services.isNotEmpty ? services.first : null;
    final manualCtrl = TextEditingController();
    var manual = services.isEmpty;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final servicePrice = manual
              ? (double.tryParse(manualCtrl.text.trim()) ?? 0)
              : (selected?.price ?? 0);
          final total = servicePrice + suppliesTotal;
          return Padding(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 4,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cobrar consulta',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 12),
                if (services.isNotEmpty) ...[
                  const Text('Servicio (honorario)', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<Object>(
                    value: manual ? 'manual' : selected,
                    isExpanded: true,
                    items: [
                      for (final s in services)
                        DropdownMenuItem(value: s, child: Text('${s.name} · ${_money(s.price)}')),
                      const DropdownMenuItem(value: 'manual', child: Text('Otro (capturar honorario)')),
                    ],
                    onChanged: (v) => setSheet(() {
                      if (v == 'manual') {
                        manual = true;
                      } else {
                        manual = false;
                        selected = v as ServiceCatalogItem;
                      }
                    }),
                  ),
                ],
                if (manual)
                  TextField(
                    controller: manualCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Honorario (MXN)'),
                    onChanged: (_) => setSheet(() {}),
                  ),
                const SizedBox(height: 12),
                _line('Honorario', servicePrice),
                _line('Insumos a cobrar', suppliesTotal),
                const Divider(),
                _line('Total', total, bold: true),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: total <= 0 && suppliesTotal <= 0
                        ? null
                        : () => Navigator.of(ctx).pop(true),
                    child: const Text('Registrar cobro'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (ok != true) return;
    final servicePrice = manual
        ? (double.tryParse(manualCtrl.text.trim()) ?? 0)
        : (selected?.price ?? 0);
    final serviceName = manual ? 'Honorario' : (selected?.name ?? 'Honorario');
    final charge = await repo.createChargeForConsultation(
      organizationId: orgId,
      consultationId: widget.consultationId,
      patientId: widget.patientId,
      siteId: widget.siteId,
      serviceName: serviceName,
      servicePrice: servicePrice,
      createdBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) {
      setState(() {});
      await _registrarPago(repo, charge);
    }
  }

  Future<void> _registrarPago(DataRepository repo, Charge charge) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Registrar pago · ${_money(charge.total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final m in const [
              ('efectivo', 'Efectivo', Icons.payments_outlined),
              ('transferencia', 'Transferencia', Icons.account_balance_outlined),
              ('tarjeta', 'Tarjeta (manual)', Icons.credit_card_outlined),
            ])
              ListTile(
                leading: Icon(m.$3),
                title: Text(m.$2),
                onTap: () => Navigator.of(ctx).pop(m.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (method == null) return;
    await repo.markChargePaid(charge.id, method,
        createdBy: ref.read(sessionProvider).user?.id);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pago registrado. Inventario descontado.')),
      );
    }
  }

  Widget _line(String label, double v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
            Text(_money(v),
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );

  /// Sitio efectivo del inventario según el alcance (0053): en 'center' se usa
  /// el sitio principal como bolsa única; en 'site' el de la consulta.
  String? _effectiveSite(DataRepository repo, String orgId) {
    if (repo.inventoryScopeFor(orgId) != 'center') return widget.siteId;
    final sites =
        repo.listSites(organizationId: orgId).where((s) => s.isActive).toList();
    return sites.isEmpty ? widget.siteId : sites.first.id;
  }

  Future<void> _suggestFromPlan(DataRepository repo) async {
    final orgId = widget.organizationId;
    if (orgId == null) return;
    final siteId = _effectiveSite(repo, orgId);
    if (siteId == null) return;

    final components =
        repo.treatmentComponentsForConsultation(widget.consultationId);
    final existingIds = repo
        .listSupplyUsageForConsultation(widget.consultationId)
        .map((u) => u.inventoryItemId)
        .whereType<String>()
        .toSet();

    // 1) Vía preferente (0076): resolución por CATEGORÍA + MEDIDA de la herida.
    final categories = <KuraTag>{
      for (final comp in components)
        if (kKuraMethodToTag[comp.method] != null)
          kKuraMethodToTag[comp.method]!
    };
    if (categories.isNotEmpty) {
      final woundId = repo.woundIdForConsultation(widget.consultationId);
      final measures =
          woundId == null ? const [] : repo.listMeasurementsForWound(woundId);
      final last = measures.isEmpty ? null : measures.last;
      final wound = woundId == null ? null : repo.getWound(woundId);
      final assessments =
          woundId == null ? const [] : repo.listAssessmentsForWound(woundId);
      final assess = assessments
              .where((a) => a.consultationId == widget.consultationId)
              .isNotEmpty
          ? assessments
              .firstWhere((a) => a.consultationId == widget.consultationId)
          : (assessments.isEmpty ? null : assessments.last);
      final resolved = repo.resolveProtocolProducts(
        organizationId: orgId,
        categories: categories,
        areaCm2: last?.areaCm2,
        volumeCm3: last?.volumeCm3,
        exudateLevel: assess?.exudateAmount.name,
        zoneGroup: ZoneGroup.forLocation(wound?.bodyLocationPrimary),
        infectionSuspected: assess?.infectionCriteria.isNotEmpty,
        siteId: siteId,
      );
      if (resolved.isNotEmpty) {
        var added = 0;
        for (final r in resolved) {
          if (!existingIds.add(r.inventoryItemId)) continue;
          await repo.addSupplyUsage(
            organizationId: orgId,
            consultationId: widget.consultationId,
            patientId: widget.patientId,
            name: r.name,
            inventoryItemId: r.inventoryItemId,
            quantity: r.quantity <= 0 ? 1 : r.quantity.ceil(),
            unitCost: r.unitCost,
            unitPrice: r.unitPrice,
            currency: r.currency,
            createdBy: ref.read(sessionProvider).user?.id,
          );
          added++;
        }
        if (added > 0) {
          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Se agregaron $added insumo(s) del protocolo.')));
          }
          return;
        }
      }
    }

    // 2) Fallback: mapeo antiguo por (método, genérico) → producto Shopify.
    final mapGroups = repo.supplyMappingGroups(orgId);
    final inventory = repo.listInventoryItems(organizationId: orgId, siteId: siteId);
    final byProduct = <String, InventoryItem>{
      for (final it in inventory)
        if (it.shopifyProductId != null) it.shopifyProductId!: it
    };
    final existing =
        repo.listSupplyUsageForConsultation(widget.consultationId)
            .map((u) => u.inventoryItemId)
            .whereType<String>()
            .toSet();

    // Un insumo genérico puede tener VARIOS productos (medidas/marcas/SKU): se
    // arman candidatos por insumo genérico y el especialista elige el producto.
    final candidates = <_PlanCandidate>[];
    for (final comp
        in repo.treatmentComponentsForConsultation(widget.consultationId)) {
      final ms =
          mapGroups[SupplyProductMapping.keyFor(comp.method, comp.product)] ??
              const [];
      final items = <InventoryItem>[];
      final localSeen = <String>{};
      for (final m in ms) {
        final item = byProduct[m.shopifyProductId];
        if (item == null || existing.contains(item.id)) continue;
        if (localSeen.add(item.id)) items.add(item);
      }
      if (items.isNotEmpty) {
        candidates.add(_PlanCandidate(comp.method, comp.product, items));
      }
    }

    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'No hay insumos del plan mapeados en el inventario de este sitio.')));
      }
      return;
    }

    // El especialista elige. Pre-marcados los insumos con una sola opción
    // (inequívocos); los que tienen varias presentaciones se eligen a mano.
    final preselected = <String>{
      for (final c in candidates)
        if (c.items.length == 1) c.items.first.id
    };
    final chosen = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlanSupplyChooser(
        candidates: candidates,
        preselected: preselected,
        money: _money,
      ),
    );
    if (chosen == null || chosen.isEmpty) return;

    var added = 0;
    for (final c in candidates) {
      for (final item in c.items) {
        if (!chosen.contains(item.id) || existing.contains(item.id)) continue;
        existing.add(item.id);
        await repo.addSupplyUsage(
          organizationId: orgId,
          consultationId: widget.consultationId,
          patientId: widget.patientId,
          name: item.name,
          inventoryItemId: item.id,
          unitCost: item.unitCost,
          unitPrice: item.unitPrice,
          currency: item.currency,
          createdBy: ref.read(sessionProvider).user?.id,
        );
        added++;
      }
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added == 0
              ? 'No se agregó ningún insumo.'
              : 'Se agregaron $added insumo(s) del plan.')));
    }
  }

  Future<void> _addManual(DataRepository repo) async {
    final orgId = widget.organizationId;
    if (orgId == null) return;
    final siteId = _effectiveSite(repo, orgId);
    if (siteId == null) return;
    final inventory = repo.listInventoryItems(organizationId: orgId, siteId: siteId);
    final item = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: inventory.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No hay inventario en el sitio de esta consulta.'))
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Elegir insumo del inventario',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    for (final it in inventory)
                      ListTile(
                        title: Text(it.name),
                        subtitle: it.unitCost == null
                            ? null
                            : Text(_money(it.unitCost!)),
                        onTap: () => Navigator.of(context).pop(it),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (item == null || !mounted) return;
    await repo.addSupplyUsage(
      organizationId: orgId,
      consultationId: widget.consultationId,
      patientId: widget.patientId,
      name: item.name,
      inventoryItemId: item.id,
      unitCost: item.unitCost,
      unitPrice: item.unitPrice,
      currency: item.currency,
      createdBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) setState(() {});
  }
}

class _UsageRow extends StatelessWidget {
  final ConsultationSupplyUsage usage;
  final ValueChanged<int> onQty;
  final ValueChanged<bool> onCharge;
  final ValueChanged<bool> onDiscount;
  final VoidCallback onDelete;
  const _UsageRow({
    required this.usage,
    required this.onQty,
    required this.onCharge,
    required this.onDiscount,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(usage.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                onPressed:
                    usage.quantity > 1 ? () => onQty(usage.quantity - 1) : null,
              ),
              Text('${usage.quantity}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                onPressed: () => onQty(usage.quantity + 1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDelete,
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              FilterChip(
                label: const Text('Cobrar'),
                selected: usage.charge,
                onSelected: onCharge,
                visualDensity: VisualDensity.compact,
              ),
              FilterChip(
                label: const Text('Descontar'),
                selected: usage.discount,
                onSelected: onDiscount,
                visualDensity: VisualDensity.compact,
              ),
              if (usage.unitCost != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 6),
                  child: Text(
                    '\$${usage.lineTotal.toStringAsFixed(2)} MXN',
                    style: const TextStyle(fontSize: 12, color: KuraColors.primary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Candidato de insumo del plan: un insumo genérico y los productos de
/// inventario que lo cubren (uno o varios, distintas medidas/marcas/SKU).
class _PlanCandidate {
  final String method;
  final String genericProduct;
  final List<InventoryItem> items;
  const _PlanCandidate(this.method, this.genericProduct, this.items);
}

/// Selector para que el especialista elija qué producto(s) del plan agregar a
/// la consulta cuando un insumo genérico tiene varias presentaciones.
class _PlanSupplyChooser extends StatefulWidget {
  final List<_PlanCandidate> candidates;
  final Set<String> preselected;
  final String Function(double) money;
  const _PlanSupplyChooser({
    required this.candidates,
    required this.preselected,
    required this.money,
  });
  @override
  State<_PlanSupplyChooser> createState() => _PlanSupplyChooserState();
}

class _PlanSupplyChooserState extends State<_PlanSupplyChooser> {
  late final Set<String> _selected = {...widget.preselected};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 2),
              child: Text('Insumos del plan',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                  'Elige el producto a usar. Los insumos con varias '
                  'presentaciones no vienen premarcados.',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final c in widget.candidates) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Text(
                        '${c.genericProduct}  ·  ${c.method}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: KuraColors.primary),
                      ),
                    ),
                    for (final item in c.items)
                      CheckboxListTile(
                        value: _selected.contains(item.id),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(item.name,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: item.unitCost == null
                            ? null
                            : Text(widget.money(item.unitCost!),
                                style: const TextStyle(fontSize: 11)),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(item.id);
                          } else {
                            _selected.remove(item.id);
                          }
                        }),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: Text('Agregar (${_selected.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
