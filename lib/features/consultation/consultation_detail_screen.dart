import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/consultation.dart';
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
      appBar: AppBar(title: const Text('Detalle de consulta')),
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
              ],
            ),
          );
        },
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
            if (m.tunneling) _MiniStat(label: 'Tunelización', value: 'Sí'),
            if (m.undermining) _MiniStat(label: 'Socavamiento', value: 'Sí'),
          ],
        ),
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
        const SizedBox(height: 16),
      ];

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
