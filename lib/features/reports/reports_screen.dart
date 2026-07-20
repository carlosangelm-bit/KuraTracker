import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show kFloatingNavBarHeight, UserMenuButton;
import '../../models/app_user.dart';
import '../../models/consultation.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/patient.dart';
import '../../models/treatment_plan.dart' show WoundPhoto, TreatmentPlan;
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';

/// Modulo de reportes (seccion 7): busca/selecciona pacientes, filtra por
/// tipo de informacion, y genera un PDF de historia clinica.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final Set<String> _selectedPatientIds = {};
  bool _includeConsultations = true;
  bool _includeFollowUps = true;
  bool _includeBackground = true;
  String _evidenceMode = 'primera_ultima'; // 'todas' | 'primera_ultima'
  bool _generating = false;
  final _recommendationsCtrl = TextEditingController();

  @override
  void dispose() {
    _recommendationsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: const [UserMenuButton()],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final patients = session.user?.role == AppRole.admin
              ? repo.listAllPatients()
              : (session.user?.staffId != null
                  ? repo.listPatientsForStaff(session.user!.staffId!)
                  : <Patient>[]);

          // Cuadro de pacientes con altura acotada (no Expanded): ~40% del
          // alto de pantalla, siempre entre 220 y 380 px, para que sea
          // usable tanto en viewports cortos de movil como en escritorio.
          final screenHeight = MediaQuery.of(context).size.height;
          final patientsBoxHeight = (screenHeight * 0.4).clamp(220.0, 380.0);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(context).viewPadding.bottom + kFloatingNavBarHeight + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Selecciona pacientes',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 220,
                        maxHeight: patientsBoxHeight,
                      ),
                      child: Card(
                        child: patients.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No hay pacientes disponibles',
                                    style: TextStyle(color: Colors.black54),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: patients.length,
                                itemBuilder: (context, i) {
                                  final p = patients[i];
                                  return CheckboxListTile(
                                    value: _selectedPatientIds.contains(p.id),
                                    title: Text(p.fullName),
                                    subtitle: Text(p.folio),
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selectedPatientIds.add(p.id);
                                      } else {
                                        _selectedPatientIds.remove(p.id);
                                      }
                                    }),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Incluir en el reporte',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    CheckboxListTile(
                      value: _includeConsultations,
                      title: const Text('Consultas'),
                      onChanged: (v) => setState(() => _includeConsultations = v ?? true),
                    ),
                    CheckboxListTile(
                      value: _includeFollowUps,
                      title: const Text('Seguimientos'),
                      onChanged: (v) => setState(() => _includeFollowUps = v ?? true),
                    ),
                    CheckboxListTile(
                      value: _includeBackground,
                      title: const Text('Antecedentes'),
                      onChanged: (v) => setState(() => _includeBackground = v ?? true),
                    ),
                    const SizedBox(height: 8),
                    Text('Evidencias', style: Theme.of(context).textTheme.titleSmall),
                    RadioListTile<String>(
                      value: 'todas',
                      groupValue: _evidenceMode,
                      title: const Text('Todas'),
                      onChanged: (v) => setState(() => _evidenceMode = v!),
                    ),
                    RadioListTile<String>(
                      value: 'primera_ultima',
                      groupValue: _evidenceMode,
                      title: const Text('Primera y última'),
                      onChanged: (v) => setState(() => _evidenceMode = v!),
                    ),
                    const SizedBox(height: 8),
                    Text('Recomendaciones para el paciente',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: KuraColors.darkText.withOpacity(0.8))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _recommendationsCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText:
                            'Indicaciones/cuidados que el profesional deja al paciente (aparecen en el PDF).',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: _generating
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(_generating ? 'Generando...' : 'Generar reporte (PDF)'),
                      style: FilledButton.styleFrom(
                        backgroundColor: KuraColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _selectedPatientIds.isEmpty || _generating
                          ? null
                          : () => _generatePdf(repo),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static final _fmtDate = DateFormat('dd/MM/yyyy');

  /// Selecciona las fotos a incluir según el modo de evidencia (todas, o solo
  /// la primera y la última por orden cronológico).
  List<WoundPhoto> _selectPhotos(List<WoundPhoto> photos) {
    final sorted = [...photos]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    if (_evidenceMode == 'todas' || sorted.length <= 2) return sorted;
    return [sorted.first, sorted.last];
  }

  /// Plan de tratamiento más reciente para una herida (recorre las consultas de
  /// más nueva a más antigua hasta encontrar uno). null si no hay.
  TreatmentPlan? _latestPlan(
      DataRepository repo, List<Consultation> consultations, String woundId) {
    for (final c in consultations) {
      final p = repo.getTreatmentPlanForConsultation(c.id, woundId);
      if (p != null) return p;
    }
    return null;
  }

  /// Carga los bytes de una foto (Supabase Storage vía signed URL, o data URL en
  /// demo) como imagen embebible en el PDF. Devuelve null si falla.
  Future<pw.ImageProvider?> _loadPhoto(String storagePath) async {
    try {
      final url = await PhotoUploadService.resolveDisplayUrl(storagePath);
      if (url.startsWith('data:')) {
        final b64 = url.substring(url.indexOf(',') + 1);
        return pw.MemoryImage(base64Decode(b64));
      }
      return await networkImage(url);
    } catch (_) {
      return null;
    }
  }

  PdfColor _brandColor(String? hex) {
    if (hex == null || hex.trim().isEmpty) return const PdfColor.fromInt(0xFF7C3AED);
    var h = hex.trim().replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const PdfColor.fromInt(0xFF7C3AED) : PdfColor.fromInt(v);
  }

  Future<pw.ImageProvider?> _loadLogo(String? logoPath) async {
    if (logoPath == null || logoPath.isEmpty) return null;
    try {
      final url = await PhotoUploadService.resolveOrgLogoUrl(logoPath);
      if (url.startsWith('data:')) {
        return pw.MemoryImage(base64Decode(url.substring(url.indexOf(',') + 1)));
      }
      return await networkImage(url);
    } catch (_) {
      return null;
    }
  }

  Future<void> _generatePdf(DataRepository repo) async {
    setState(() => _generating = true);
    try {
      final doc = pw.Document();
      final generatedAt = _fmtDate.format(DateTime.now());

      // Branding del centro del usuario (logo + color) para el encabezado.
      final userOrgId = ref.read(sessionProvider).user?.organizationId;
      final orgs = userOrgId == null
          ? const []
          : repo.listOrganizations().where((o) => o.id == userOrgId).toList();
      final org = orgs.isEmpty ? null : orgs.first;
      final brandColor = _brandColor(org?.brandPrimaryColor);
      final brandLogo = await _loadLogo(org?.brandLogoPath);
      final centerName = org?.name ?? 'KuraTracker';

      for (final patientId in _selectedPatientIds) {
        final patient = repo.getPatient(patientId);
        if (patient == null) continue;
        final wounds = repo.listWoundsForPatient(patientId);
        final consultations = repo.listConsultationsForPatient(patientId);

        // Precarga de fotos por herida (async), según el modo de evidencia.
        final photosByWound = <String, List<pw.Widget>>{};
        for (final w in wounds) {
          final selected = _selectPhotos(repo.listPhotosForWound(w.id));
          final widgets = <pw.Widget>[];
          for (final ph in selected) {
            final img = await _loadPhoto(ph.storagePath);
            if (img == null) continue;
            widgets.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.ClipRRect(
                    horizontalRadius: 4,
                    verticalRadius: 4,
                    child: pw.Image(img, width: 150, height: 150, fit: pw.BoxFit.cover),
                  ),
                  pw.Text(
                    '${_fmtDate.format(ph.takenAt)}${ph.isBaseline ? ' · basal' : ''}',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ],
              ),
            );
          }
          if (widgets.isNotEmpty) photosByWound[w.id] = widgets;
        }

        final followUps = consultations
            .where((c) => c.visitType == VisitType.seguimiento)
            .toList();

        doc.addPage(
          pw.MultiPage(
            build: (context) => [
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                margin: const pw.EdgeInsets.only(bottom: 10),
                decoration: pw.BoxDecoration(
                  border: pw.Border(left: pw.BorderSide(color: brandColor, width: 4)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (brandLogo != null) ...[
                      pw.Image(brandLogo, height: 40),
                      pw.SizedBox(width: 10),
                    ],
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(centerName,
                              style: pw.TextStyle(
                                  fontSize: 15,
                                  fontWeight: pw.FontWeight.bold,
                                  color: brandColor)),
                          pw.Text('Reporte clínico de herida · $generatedAt',
                              style: const pw.TextStyle(fontSize: 9)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.Text(patient.fullName,
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('Folio: ${patient.folio}'),
              pw.Text('Edad: ${patient.age ?? '-'} · Sexo: ${patient.sex ?? '-'}'),
              if (_includeBackground &&
                  (patient.backgroundNotes ?? '').isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Text('Antecedentes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(patient.backgroundNotes!),
              ],
              pw.SizedBox(height: 16),
              pw.Text('Heridas registradas',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              if (wounds.isEmpty) pw.Text('Sin heridas registradas.'),
              ...wounds.map((w) {
                final measurements = repo.listMeasurementsForWound(w.id); // asc por fecha
                final photos = photosByWound[w.id];
                final last = measurements.isNotEmpty ? measurements.last : null;
                final first = measurements.isNotEmpty ? measurements.first : null;
                final plan = _latestPlan(repo, consultations, w.id);

                // Avance: % de reducción de área entre la primera y la última.
                String? progreso;
                if (measurements.length >= 2 && first!.areaCm2 > 0) {
                  final diff = first.areaCm2 - last!.areaCm2;
                  final pct = (diff / first.areaCm2) * 100;
                  final verbo = pct >= 0 ? 'reducción' : 'aumento';
                  progreso =
                      'El área pasó de ${first.areaCm2.toStringAsFixed(1)} cm² '
                      '(${_fmtDate.format(first.measuredAt)}) a '
                      '${last.areaCm2.toStringAsFixed(1)} cm² '
                      '(${_fmtDate.format(last.measuredAt)}): '
                      '$verbo del ${pct.abs().toStringAsFixed(0)}%.';
                }

                // Composición del tejido (última medición), si se registró.
                final comp = <String>[];
                if (last != null && last.bedCompositionSum > 0) {
                  if (last.granulationPct > 0) comp.add('granulación ${last.granulationPct.toStringAsFixed(0)}%');
                  if (last.sloughPct > 0) comp.add('esfacelo ${last.sloughPct.toStringAsFixed(0)}%');
                  if (last.necrosisPct > 0) comp.add('necrosis ${last.necrosisPct.toStringAsFixed(0)}%');
                  if (last.epithelializationPct > 0) comp.add('epitelización ${last.epithelializationPct.toStringAsFixed(0)}%');
                }

                pw.Widget label(String t) =>
                    pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor));

                return pw.Container(
                  margin: const pw.EdgeInsets.only(top: 10, bottom: 6),
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.5),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Diagnóstico
                      pw.Text('${w.etiology.label}${w.subtype != null ? ' — ${w.subtype}' : ''}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      pw.Text('Localización: ${w.bodyLocationPrimary}',
                          style: const pw.TextStyle(fontSize: 9)),
                      if (w.wuwhsGrade != null)
                        pw.Text('Grado de severidad (WUWHS): ${w.wuwhsGrade!.name.toUpperCase()}',
                            style: const pw.TextStyle(fontSize: 9)),

                      // Condición actual
                      pw.SizedBox(height: 6),
                      label('Condición actual'),
                      if (last != null)
                        pw.Text(
                          'Tamaño: ${last.areaCm2.toStringAsFixed(1)} cm² '
                          '(${last.lengthCm.toStringAsFixed(1)} × ${last.widthCm.toStringAsFixed(1)} cm)'
                          '${last.depthCm > 0 ? ', profundidad ${last.depthCm.toStringAsFixed(1)} cm' : ''}'
                          ' · ${_fmtDate.format(last.measuredAt)}',
                          style: const pw.TextStyle(fontSize: 9),
                        )
                      else
                        pw.Text('Sin mediciones registradas.', style: const pw.TextStyle(fontSize: 9)),
                      if (comp.isNotEmpty)
                        pw.Text('Composición del tejido: ${comp.join(', ')}.',
                            style: const pw.TextStyle(fontSize: 9)),

                      // Avance
                      if (progreso != null) ...[
                        pw.SizedBox(height: 6),
                        label('Avance de la herida'),
                        pw.Text(progreso, style: const pw.TextStyle(fontSize: 9)),
                      ],

                      // Tratamiento establecido
                      if (plan != null) ...[
                        pw.SizedBox(height: 6),
                        label('Tratamiento establecido'),
                        if ((plan.finalDescription ?? '').isNotEmpty)
                          pw.Text(plan.finalDescription!, style: const pw.TextStyle(fontSize: 9)),
                        ...plan.components.map((cmp) => pw.Text(
                              '· ${cmp.method}${cmp.product.isNotEmpty ? ': ${cmp.product}' : ''}',
                              style: const pw.TextStyle(fontSize: 9),
                            )),
                      ],

                      // Evidencia
                      if (photos != null) ...[
                        pw.SizedBox(height: 6),
                        label(_evidenceMode == 'primera_ultima'
                            ? 'Evidencia fotográfica (antes / después)'
                            : 'Evidencia fotográfica'),
                        pw.SizedBox(height: 4),
                        pw.Wrap(spacing: 8, runSpacing: 8, children: photos),
                      ],
                    ],
                  ),
                );
              }),
              if (_includeConsultations) ...[
                pw.SizedBox(height: 16),
                pw.Text('Consultas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (consultations.isEmpty) pw.Text('Sin consultas registradas.'),
                ...consultations.map((c) => pw.Text(
                      '${_fmtDate.format(c.visitDate)} — ${c.visitType.label}',
                    )),
              ],
              if (_includeFollowUps && followUps.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text('Notas de seguimiento',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ...followUps.map((c) => pw.Container(
                      margin: const pw.EdgeInsets.only(top: 6),
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(_fmtDate.format(c.visitDate),
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          if ((c.followUpCareType ?? '').isNotEmpty)
                            pw.Text('Tipo de atención: ${c.followUpCareType}',
                                style: const pw.TextStyle(fontSize: 9)),
                          if ((c.followUpProcedureDesc ?? '').isNotEmpty)
                            pw.Text('Procedimiento: ${c.followUpProcedureDesc}',
                                style: const pw.TextStyle(fontSize: 9)),
                          if ((c.followUpMaterialsUsed ?? '').isNotEmpty)
                            pw.Text('Material: ${c.followUpMaterialsUsed}',
                                style: const pw.TextStyle(fontSize: 9)),
                          if ((c.followUpEvolution ?? '').isNotEmpty)
                            pw.Text('Evolución: ${c.followUpEvolution}',
                                style: const pw.TextStyle(fontSize: 9)),
                          if ((c.followUpSignedBy ?? '').isNotEmpty)
                            pw.Text(
                                'Firma: ${c.followUpSignedBy}'
                                '${(c.followUpSignedLicense ?? '').isNotEmpty ? ' · Céd. ${c.followUpSignedLicense}' : ''}',
                                style: const pw.TextStyle(fontSize: 9)),
                        ],
                      ),
                    )),
              ],
              if (_recommendationsCtrl.text.trim().isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text('Recomendaciones para el paciente',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: brandColor)),
                pw.SizedBox(height: 4),
                pw.Text(_recommendationsCtrl.text.trim()),
              ],
              pw.SizedBox(height: 20),
              pw.Text(
                'Herramienta de apoyo a la decisión clínica. No sustituye el juicio del '
                'profesional de salud.',
                style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
              ),
            ],
          ),
        );
      }

      await Printing.layoutPdf(onLayout: (format) => doc.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}
