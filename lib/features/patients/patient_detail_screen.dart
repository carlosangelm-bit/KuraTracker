import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/center_type.dart';
import '../../models/module_key.dart';
import '../../models/vac_therapy.dart';
import '../vac/vac_therapy_form.dart';
import '../../engine/labs/lab_domain_scoring.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import 'patient_labs_screen.dart' show severityColor;
import '../../models/app_user.dart';
import '../../models/antecedentes.dart';
import '../../models/patient_diagnosis.dart';
import '../risk/risk_theme.dart';
import '../../models/patient.dart';
import '../../models/wound.dart';
import '../../models/consultation.dart';
import '../../models/consent.dart';
import '../../services/csv_download.dart';
import '../../services/data_repository.dart';
import '../../services/export/record_export.dart';
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

  /// Exporta el expediente del paciente como CARPETA comprimida (ZIP): CSVs +
  /// fotos originales por herida/fecha (paquete de salida, reemplaza el PDF).
  /// Una foto que falle no aborta la entrega: se anota en el manifiesto.
  Future<void> _exportPatientRecord(
      BuildContext context, DataRepository repo, Patient patient) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
        content: Text('Preparando el expediente de ${patient.folio}…'),
        duration: const Duration(seconds: 30)));
    try {
      final result = await RecordExportService.buildPatientFiles(repo, patient);
      final folioDir = RecordExportService.sanitize(patient.folio);
      final files = <ExportedFile>[
        ...result.files,
        ExportedFile('$folioDir/manifiesto.csv',
            RecordExportService.patientManifestCsv(patient, result)),
      ];
      final bytes = RecordExportService.zip(files);
      final fecha = DateTime.now().toIso8601String().substring(0, 10);
      final filename = 'expediente_${folioDir}_$fecha.zip';
      await downloadBytes(filename, bytes, 'application/zip');
      // Registro de divulgación (0101): DESPUÉS de entregar la descarga.
      final user = ref.read(sessionProvider).user;
      await repo.recordDataDisclosure(
        organizationId: patient.organizationId ?? user?.organizationId,
        actorId: user?.id,
        actorEmail: user?.email,
        kind: 'expediente_paciente',
        scope: {'patient_id': patient.id, 'folio': patient.folio},
        recordCount: files.length,
        patientCount: 1,
        photoCount: result.photoCount,
        missingCount: result.photoMissing,
        fileName: filename,
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
          content: Text(result.photoMissing == 0
              ? 'Expediente exportado: ${result.photoCount} foto(s).'
              : 'Expediente exportado: ${result.photoCount} foto(s), '
                  '${result.photoMissing} faltante(s) (ver manifiesto.csv).')));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger
          .showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  /// Plan de alta / egreso de una herida: elige el motivo de egreso + una
  /// explicación libre y cierra la herida (Prompt 5 / feedback de María).
  Future<void> _openDischargePlan(
      BuildContext context, DataRepository repo, Wound wound) async {
    var motivo = MotivoEgreso.cierre;
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Plan de alta de la herida'),
        content: StatefulBuilder(
          builder: (ctx, setDlg) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<MotivoEgreso>(
                value: motivo,
                decoration: const InputDecoration(
                    labelText: 'Motivo de egreso', border: OutlineInputBorder()),
                items: [
                  for (final m in MotivoEgreso.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (v) => setDlg(() => motivo = v ?? MotivoEgreso.cierre),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Plan de alta / explicación (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Egresar herida')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await repo.closeWound(wound.id, motivo,
        dischargeNote: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
    if (mounted) setState(() {});
  }

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
          // Enfermería (0045) NO diagnostica ni cambia protocolo: se ocultan los
          // botones de escritura clínica (editar expediente, nueva consulta,
          // registrar herida/seguimiento, comorbilidades/diagnósticos). Puede
          // leer todo + reportar (riesgo/eventos adversos) + prevención.
          final canWrite = ref.watch(sessionProvider).user?.canDiagnose ?? true;
          // Exportar el expediente (paquete de salida / divulgación): admin/master.
          // Permisos por los getters del conjunto de roles, nunca por role == x.
          final exportUser = ref.watch(sessionProvider).user;
          final canExportRecord =
              (exportUser?.isAdmin ?? false) || (exportUser?.isMaster ?? false);
          final wounds = repo.listWoundsForPatient(patient.id);
          final consultations = repo.listConsultationsForPatient(patient.id);
          final comorbidities = repo.listComorbidities(patient.id);
          final diagnoses = repo.listDiagnoses(patient.id);
          // Si el paciente tiene UNA sola herida activa, el seguimiento se
          // muestra embebido aquí mismo (menos clicks): no hace falta entrar a
          // la pantalla de seguimiento.
          final activeWounds = wounds.where((w) => w.isActive).toList();
          final singleActiveWound = activeWounds.length == 1 ? activeWounds.first : null;

          // Centra el contenido en desktop (la SliverAppBar sigue a todo el
          // ancho); evita que el expediente se estire de borde a borde.
          final screenW = MediaQuery.of(context).size.width;
          final contentSidePad = screenW > 1040 ? (screenW - 1000) / 2 : 20.0;

          // Hospital: la herramienta es apoyo al MANEJO PREVENTIVO, no un
          // expediente de heridas. Se prioriza Prevención/Riesgo y el resto del
          // expediente queda bajo "Avanzado" (por si el profesional lo usa).
          final isHospital =
              ref.watch(sessionProvider).activeCenterType == CenterType.hospital;

          // Tarjetas de sección (se instancian una vez; solo una rama del árbol
          // las monta, así que reutilizarlas entre ramas es seguro).
          final comorbidityCard = _ComorbidityCard(
              patientId: patient.id,
              comorbidities: comorbidities,
              canWrite: canWrite);
          final diagnosesCard = _DiagnosesCard(
              patientId: patient.id, diagnoses: diagnoses, canWrite: canWrite);
          // Laboratorios (0070 + dominio clínico 0073): los más recientes
          // alimentan el motor (albúmina) y se puntúan 0–3 (banderas).
          final latestLab = repo.latestPatientLab(patient.id);
          final labsSummary =
              latestLab == null ? null : scoreClinicalDomain(latestLab);
          final labsWorst = labsSummary?.worst;
          final labsCard = Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.biotech_outlined,
                  color: KuraColors.primary),
              title: const Text('Laboratorios'),
              subtitle: Text(latestLab == null
                  ? 'Registrar glucosa, albúmina, HbA1c, SatO₂…'
                  : 'Último: ${_dateFmt.format(latestLab.takenAt)}'
                      '${latestLab.glucoseMgDl != null ? ' · Glu ${latestLab.glucoseMgDl!.toStringAsFixed(0)}' : ''}'
                      '${latestLab.albuminGdl != null ? ' · Alb ${latestLab.albuminGdl}' : ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (labsWorst != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: severityColor(labsWorst).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        (labsSummary!.highCount > 0)
                            ? '${labsWorst.label} · ${labsSummary.highCount}'
                            : labsWorst.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: severityColor(labsWorst)),
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              onTap: () => context.go('/patients/${patient.id}/labs'),
            ),
          );
          final riskCard = _RiskCard(patientId: patient.id);
          // Terapia VAC (módulo transversal): entrada desde el paciente. Se
          // muestra solo si el módulo está habilitado para el centro.
          final vacEnabled =
              ref.watch(enabledModulesProvider).contains(ModuleKey.vac);
          final activeVac = repo.activeVacTherapy(patient.id);
          final vacOrg = patient.organizationId;
          final vacCard = Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading:
                  const Icon(Icons.healing_outlined, color: KuraColors.primary),
              title: const Text('Terapia VAC'),
              subtitle: Text(activeVac == null
                  ? 'Sin terapia activa · registrar'
                  : '${activeVac.equipment.label}'
                      '${activeVac.settingsLabel.isNotEmpty ? ' · ${activeVac.settingsLabel}' : ''}'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () async {
                if (activeVac != null) {
                  context.push('/vac/${activeVac.id}');
                } else if (vacOrg != null) {
                  final ok = await showVacTherapyForm(context, ref,
                      orgId: vacOrg, patientId: patient.id);
                  if (ok == true && mounted) setState(() {});
                }
              },
            ),
          );
          final caregiversCard = _CaregiversCard(
              patientId: patient.id, organizationId: patient.organizationId);
          final assignmentCard = _AssignSpecialistCard(
              patientId: patient.id, organizationId: patient.organizationId);
          final consentsCard =
              _ConsentsSummaryCard(patientId: patient.id, repo: repo);
          final cobrosCard = _CobrosCard(
              patientId: patient.id,
              organizationId: patient.organizationId,
              repo: repo);
          final adverseSection =
              _AdverseEventsSection(patientId: patient.id, repo: repo);
          final referralsCard = Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              onTap: () => context.go('/patients/${patient.id}/referrals'),
              leading: const Icon(Icons.forward_to_inbox_outlined,
                  color: KuraColors.primary),
              title: const Text('Referencias / interconsultas'),
              subtitle: Text(
                () {
                  final refs = repo.listReferralsForPatient(patient.id);
                  final pend = refs.where((r) => !r.isRespondida).length;
                  if (refs.isEmpty) return 'Generar formato de referencia';
                  return '${refs.length} referencia(s)'
                      '${pend > 0 ? ' · $pend pendiente(s) de respuesta' : ''}';
                }(),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
            ),
          );

          // Bloque de heridas (título + registrar + tarjetas + seguimiento
          // embebido de la herida única activa).
          final woundsBlock = <Widget>[
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
                if (canWrite)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Registrar herida'),
                    onPressed: () => context
                        .go('/patients/${patient.id}/consultation/new'),
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
                    canWrite: canWrite,
                    showFollowUpButton: singleActiveWound == null ||
                        w.id != singleActiveWound.id,
                    onDischarge: () => _openDischargePlan(context, repo, w),
                  )),
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
                  if (canWrite)
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
          ];

          // Historial de consultas.
          final consultationsBlock = <Widget>[
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
                      // El borrador abre el detalle: ahí se cobra y hay botón
                      // para completar la consulta clínica.
                      onTap: () => context.go(
                          '/patients/${widget.patientId}/consultation/${c.id}'),
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
          ];

          // Todo lo que NO es prevención/riesgo (el expediente de heridas).
          final advancedSections = <Widget>[
            comorbidityCard,
            const SizedBox(height: 16),
            diagnosesCard,
            const SizedBox(height: 16),
            labsCard,
            const SizedBox(height: 16),
            assignmentCard,
            const SizedBox(height: 16),
            caregiversCard,
            const SizedBox(height: 16),
            consentsCard,
            const SizedBox(height: 16),
            cobrosCard,
            const SizedBox(height: 16),
            ...woundsBlock,
            const SizedBox(height: 24),
            ...consultationsBlock,
            const SizedBox(height: 24),
            adverseSection,
            const SizedBox(height: 16),
            referralsCard,
          ];

          final bodyChildren = <Widget>[
            _PatientHeaderCard(patient: patient, dateFmt: _dateFmt),
            const SizedBox(height: 16),
            if (isHospital) ...[
              // Prevención/Riesgo primero (lo que se usa en hospital).
              riskCard,
              const SizedBox(height: 16),
              if (vacEnabled) ...[
                vacCard,
                const SizedBox(height: 16),
              ],
              _AdvancedSection(children: advancedSections),
              const SizedBox(height: 40),
            ] else ...[
              comorbidityCard,
              const SizedBox(height: 16),
              diagnosesCard,
              const SizedBox(height: 16),
              labsCard,
              const SizedBox(height: 16),
              riskCard,
              const SizedBox(height: 16),
              if (vacEnabled) ...[
                vacCard,
                const SizedBox(height: 16),
              ],
              assignmentCard,
              const SizedBox(height: 16),
              caregiversCard,
              const SizedBox(height: 16),
              consentsCard,
              const SizedBox(height: 16),
              cobrosCard,
              ...woundsBlock,
              const SizedBox(height: 24),
              ...consultationsBlock,
              const SizedBox(height: 24),
              adverseSection,
              const SizedBox(height: 16),
              referralsCard,
              const SizedBox(height: 40),
            ],
          ];

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Volver',
                  // Vuelve al PASO ANTERIOR real (lista, Inicio, agenda, etc.);
                  // si no hay pila (enlace directo), cae a la lista de pacientes.
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go('/patients'),
                ),
                title: Text(patient.fullName),
                pinned: true,
                actions: [
                  if (canExportRecord)
                    IconButton(
                      icon: const Icon(Icons.folder_zip_outlined),
                      tooltip: 'Exportar expediente (ZIP)',
                      onPressed: () =>
                          _exportPatientRecord(context, repo, patient),
                    ),
                  if (canWrite) ...[
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
                ],
              ),
              SliverPadding(
                padding:
                    EdgeInsets.fromLTRB(contentSidePad, 20, contentSidePad, 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(bodyChildren),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Sección "Avanzado" (hospital): agrupa colapsado el resto del expediente
/// (heridas, consultas, cobros, referencias…) para priorizar Prevención/Riesgo.
class _AdvancedSection extends StatelessWidget {
  final List<Widget> children;
  const _AdvancedSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.tune, color: KuraColors.primary),
          title: const Text('Avanzado',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text(
              'Expediente completo: heridas, consultas, cobros, referencias…'),
          childrenPadding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientHeaderCard extends StatelessWidget {
  final Patient patient;
  final DateFormat dateFmt;
  const _PatientHeaderCard({required this.patient, required this.dateFmt});

  // Muestra un campo (antecedentes / alergias / medicamentos) como chips a
  // partir del texto guardado (un concepto por línea; ";"/"," como respaldo).
  Widget _labeledChips(String label, String? raw,
      {required Color color, bool danger = false}) {
    final items = (raw ?? '')
        .split(RegExp(r'[\n;,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: items
              .map((t) => Chip(
                    label: Text(t, style: const TextStyle(fontSize: 12)),
                    backgroundColor: danger
                        ? KuraColors.danger.withOpacity(0.10)
                        : KuraColors.chipBg,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ))
              .toList(),
        ),
      ],
    );
  }

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
            // KT-17: sugerencia de derivación por edad. ≥65 → geriatría; <65 se
            // sugiere valorar derivación sin asumir la especialidad (según cuadro).
            if (patient.age != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KuraColors.infoBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.medical_information_outlined,
                        size: 18, color: KuraColors.infoBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        patient.age! >= 65
                            ? 'Paciente ≥65 años: sugerir derivación a geriatría.'
                            : 'Paciente <65 años: valorar derivación a especialista según el cuadro clínico.',
                        style: TextStyle(
                            fontSize: 12,
                            color: KuraColors.darkText.withOpacity(0.8)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if ((patient.backgroundNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              _labeledChips('Antecedentes', patient.backgroundNotes,
                  color: KuraColors.darkText.withOpacity(0.6)),
            ],
            if ((patient.allergies ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _labeledChips('Alergias', patient.allergies,
                  color: KuraColors.danger, danger: true),
            ],
            if ((patient.activeMedications ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _labeledChips('Medicamentos activos', patient.activeMedications,
                  color: KuraColors.darkText.withOpacity(0.6)),
            ],
            if ((patient.surgicalHistory ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Antecedentes quirúrgicos',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: KuraColors.darkText.withOpacity(0.6))),
              const SizedBox(height: 4),
              Text(patient.surgicalHistory!),
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
  final bool canWrite;
  const _ComorbidityCard(
      {required this.patientId,
      required this.comorbidities,
      this.canWrite = true});

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
        // Enfermería: solo lectura (no navega a la pantalla editable).
        onTap: canWrite
            ? () => context.go('/patients/$patientId/comorbidities')
            : null,
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
                  if (canWrite) const Icon(Icons.chevron_right, size: 18),
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

/// Tarjeta (solo admin) para gestionar qué usuarios CUIDADOR pueden monitorear
/// a este paciente (caregiver_patient_assignments, Fase 3). El cuidador solo ve
/// —en modo lectura— a los pacientes que aquí se le asignen.
/// Asignación del paciente a un especialista (Kurador/médico). Clave para los
/// pacientes creados por Acuity/eKare que llegan sin dueño. Solo admin/master.
class _AssignSpecialistCard extends ConsumerStatefulWidget {
  final String patientId;
  final String? organizationId;
  const _AssignSpecialistCard(
      {required this.patientId, required this.organizationId});
  @override
  ConsumerState<_AssignSpecialistCard> createState() =>
      _AssignSpecialistCardState();
}

class _AssignSpecialistCardState extends ConsumerState<_AssignSpecialistCard> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isAdmin = session.user?.role == AppRole.admin;
    final isMaster = session.user?.isMaster ?? false;
    if (!isAdmin && !isMaster) return const SizedBox.shrink();
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;
    if (repo == null) return const SizedBox.shrink();

    final assigned = repo.staffForPatient(widget.patientId);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Especialista asignado',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Asignar'),
                  onPressed: () => _openAssign(repo),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (assigned.isEmpty)
              Text('Sin especialista asignado.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ...assigned.map((s) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(s.fullName),
                    subtitle: Text(s.roleTitle),
                    trailing: IconButton(
                      tooltip: 'Quitar',
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        await repo.unassignPatientFromStaff(
                            widget.patientId, s.id);
                        if (mounted) setState(() {});
                      },
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Future<void> _openAssign(DataRepository repo) async {
    final assignedIds = repo
        .staffForPatient(widget.patientId)
        .map((s) => s.id)
        .toSet();
    final candidates = repo
        .listStaff(organizationId: widget.organizationId)
        .where((s) => s.isActive && !assignedIds.contains(s.id))
        .toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Asignar especialista'),
        content: SizedBox(
          width: 380,
          child: candidates.isEmpty
              ? const Text('No hay personal disponible en el centro.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: candidates
                        .map((s) => ListTile(
                              leading: const Icon(Icons.person_outline),
                              title: Text(s.fullName),
                              subtitle: Text(s.roleTitle),
                              onTap: () async {
                                await repo.assignPatientToStaff(
                                    widget.patientId, s.id);
                                if (dialogCtx.mounted) {
                                  Navigator.of(dialogCtx).pop();
                                }
                                if (mounted) setState(() {});
                              },
                            ))
                        .toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }
}

class _CaregiversCard extends ConsumerStatefulWidget {
  final String patientId;
  final String? organizationId;
  const _CaregiversCard(
      {required this.patientId, required this.organizationId});

  @override
  ConsumerState<_CaregiversCard> createState() => _CaregiversCardState();
}

class _CaregiversCardState extends ConsumerState<_CaregiversCard> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    // Solo el admin del centro gestiona cuidadores.
    if (session.user?.role != AppRole.admin) return const SizedBox.shrink();
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;
    if (repo == null) return const SizedBox.shrink();

    final usersById = {for (final u in repo.listUsers()) u.id: u};
    final assignments =
        repo.listCaregiverAssignments(patientId: widget.patientId);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_heart_outlined, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Cuidadores que monitorean',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Asignar'),
                  onPressed: () => _openAssign(repo, usersById),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (assignments.isEmpty)
              Text('Ningún cuidador asignado.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ...assignments.map((a) {
                final name =
                    usersById[a.caregiverProfileId]?.fullName ?? 'Cuidador';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text(name),
                  trailing: IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await repo.removeCaregiverAssignment(a.id);
                      setState(() {});
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _openAssign(
      DataRepository repo, Map<String, AppUser> usersById) async {
    final assigned = repo
        .listCaregiverAssignments(patientId: widget.patientId)
        .map((a) => a.caregiverProfileId)
        .toSet();
    // Usuarios con rol cuidador aún no asignados a este paciente. Capacidad
    // positiva: quien TIENE el rol cuidador es asignable (punto 6 §2 A).
    final candidates = usersById.values
        .where((u) => u.hasRole(AppRole.cuidador) && !assigned.contains(u.id))
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Asignar cuidador'),
        content: SizedBox(
          width: 380,
          child: candidates.isEmpty
              ? const Text(
                  'No hay usuarios cuidador disponibles en el centro. '
                  'Créalos primero (rol Cuidador) desde Administración/Plataforma.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: candidates
                      .map((u) => ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text(u.fullName),
                            subtitle: Text(u.email,
                                overflow: TextOverflow.ellipsis),
                            onTap: () async {
                              await repo.assignCaregiverToPatient(
                                caregiverProfileId: u.id,
                                patientId: widget.patientId,
                                organizationId: widget.organizationId,
                                assignedBy:
                                    ref.read(sessionProvider).user?.id,
                              );
                              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                              setState(() {});
                            },
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cerrar'),
          ),
        ],
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
        onTap: () => context.push('/patients/$patientId/risk'),
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
  final bool canWrite;
  const _DiagnosesCard(
      {required this.patientId, required this.diagnoses, this.canWrite = true});

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
        // Enfermería: solo lectura (no navega a la pantalla editable).
        onTap:
            canWrite ? () => context.go('/patients/$patientId/diagnoses') : null,
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
                  if (canWrite) const Icon(Icons.chevron_right, size: 18),
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
  // Abre el "Plan de alta" (egreso de la herida). Lo provee el padre para poder
  // refrescar tras cerrar la herida.
  final VoidCallback? onDischarge;
  // Enfermería: solo lectura de la herida (oculta valoración/plan de alta).
  final bool canWrite;
  const _WoundCard({
    required this.patientId,
    required this.wound,
    required this.repo,
    this.showFollowUpButton = true,
    this.onDischarge,
    this.canWrite = true,
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
                if (canWrite)
                  TextButton.icon(
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('Nueva valoración'),
                    onPressed: () =>
                        context.go('/patients/$patientId/wound/${wound.id}/capture'),
                  ),
                if (canWrite && wound.isActive && onDischarge != null)
                  TextButton.icon(
                    icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                    label: const Text('Plan de alta'),
                    onPressed: onDischarge,
                  ),
              ],
            ),
            if (!wound.isActive && wound.motivoEgreso != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KuraColors.chipBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Egresada · ${wound.motivoEgreso!.label}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                    if ((wound.dischargeNote ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(wound.dischargeNote!,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            ],
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

/// Resumen de cobros del paciente en el expediente (módulo comercial, Fase C).
/// Solo se muestra en centros con Insumos premium y si hay cobros.
class _CobrosCard extends StatelessWidget {
  final String patientId;
  final String? organizationId;
  final DataRepository repo;
  const _CobrosCard({
    required this.patientId,
    required this.organizationId,
    required this.repo,
  });

  @override
  Widget build(BuildContext context) {
    if (!repo.premiumInsumosFor(organizationId)) return const SizedBox.shrink();
    final t = repo.patientChargeTotals(patientId);
    if (t.paid == 0 && t.pending == 0) return const SizedBox.shrink();
    String money(double v) => '\$${v.toStringAsFixed(2)} MXN';
    return Column(
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.point_of_sale_outlined, color: KuraColors.primary),
            title: const Text('Cobros', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Pagado: ${money(t.paid)}'
                '${t.pending > 0 ? '  ·  Pendiente: ${money(t.pending)}' : ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/comercial'),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
