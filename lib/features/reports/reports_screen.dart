import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../models/consultation.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/patient.dart';
import '../../services/data_repository.dart';

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
      appBar: AppBar(title: const Text('Reportes')),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final patients = session.user?.role == AppRole.admin
              ? repo.listAllPatients()
              : (session.user?.staffId != null
                  ? repo.listPatientsForStaff(session.user!.staffId!)
                  : <Patient>[]);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Selecciona pacientes',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Card(
                        child: ListView.builder(
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

  Future<void> _generatePdf(DataRepository repo) async {
    setState(() => _generating = true);
    final doc = pw.Document();

    for (final patientId in _selectedPatientIds) {
      final patient = repo.getPatient(patientId);
      if (patient == null) continue;
      final wounds = repo.listWoundsForPatient(patientId);
      final consultations = repo.listConsultationsForPatient(patientId);

      doc.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Header(text: 'KuraTracker — Historia clínica'),
            pw.Text(patient.fullName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Folio: ${patient.folio}'),
            pw.Text('Edad: ${patient.age ?? '-'} · Sexo: ${patient.sex ?? '-'}'),
            if (_includeBackground && patient.backgroundNotes != null) ...[
              pw.SizedBox(height: 12),
              pw.Text('Antecedentes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(patient.backgroundNotes!),
            ],
            pw.SizedBox(height: 16),
            pw.Text('Heridas registradas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ...wounds.map((w) {
              final measurements = repo.listMeasurementsForWound(w.id);
              return pw.Container(
                margin: const pw.EdgeInsets.only(top: 8, bottom: 8),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('${w.etiology.label} — ${w.subtype ?? ''}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('Localización: ${w.bodyLocationPrimary}'),
                    if (measurements.isNotEmpty)
                      pw.Text(
                        'Última medición: ${measurements.last.areaCm2.toStringAsFixed(1)} cm² '
                        '(${measurements.length} mediciones registradas)',
                      ),
                  ],
                ),
              );
            }),
            if (_includeConsultations) ...[
              pw.SizedBox(height: 16),
              pw.Text('Consultas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ...consultations.map((c) => pw.Text(
                    '${c.visitDate.toIso8601String().substring(0, 10)} — ${c.visitType.label}',
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
    setState(() => _generating = false);
  }
}
