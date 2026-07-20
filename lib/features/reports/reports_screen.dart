import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show kFloatingNavBarHeight, UserMenuButton;
import '../../models/app_user.dart';
import '../../models/consultation.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/patient.dart';
import '../../models/treatment_plan.dart' show WoundPhoto;
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

  Future<void> _generatePdf(DataRepository repo) async {
    setState(() => _generating = true);
    try {
      final doc = pw.Document();
      final generatedAt = _fmtDate.format(DateTime.now());

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
              pw.Header(text: 'KuraTracker — Historia clínica'),
              pw.Text(patient.fullName,
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('Folio: ${patient.folio}'),
              pw.Text('Edad: ${patient.age ?? '-'} · Sexo: ${patient.sex ?? '-'}'),
              pw.Text('Generado: $generatedAt', style: const pw.TextStyle(fontSize: 9)),
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
                final measurements = repo.listMeasurementsForWound(w.id);
                final photos = photosByWound[w.id];
                return pw.Container(
                  margin: const pw.EdgeInsets.only(top: 8, bottom: 8),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('${w.etiology.label}${w.subtype != null ? ' — ${w.subtype}' : ''}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('Localización: ${w.bodyLocationPrimary}'),
                      if (measurements.isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text('Mediciones (${measurements.length}):',
                            style: const pw.TextStyle(fontSize: 9)),
                        ...measurements.map((m) => pw.Text(
                              '· ${_fmtDate.format(m.measuredAt)} — ${m.areaCm2.toStringAsFixed(1)} cm²',
                              style: const pw.TextStyle(fontSize: 9),
                            )),
                      ],
                      if (photos != null) ...[
                        pw.SizedBox(height: 6),
                        pw.Text('Evidencia fotográfica:', style: const pw.TextStyle(fontSize: 9)),
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
