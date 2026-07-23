import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../engine/models/kura_engine_enums.dart';
import '../models/adverse_event.dart';
import '../models/patient.dart';
import '../models/preventive_task.dart';
import 'data_repository.dart';

/// Genera el REPORTE HOSPITALARIO DE PREVENCIÓN (LPP) para uno o varios
/// pacientes: internamiento, riesgo (Braden), comorbilidades, diagnósticos,
/// cumplimiento de las rondas, bitácora operativa e indicaciones al cuidador.
///
/// Es el análogo del reporte de herida (que no aplica en Hospital, donde el
/// paciente puede no tener heridas). Se construye desde los datos que ya se
/// registran en el flujo de prevención. Exporta con el diálogo nativo.
Future<void> generatePreventionReportPdf({
  required DataRepository repo,
  required List<Patient> patients,
  required String? organizationId,
  DateTime? now,
}) async {
  final ref = now ?? DateTime.now();
  final fmtDate = DateFormat('dd/MM/yyyy');
  final fmtDateTime = DateFormat('dd/MM/yyyy HH:mm');

  final org = repo.organizationById(organizationId);
  final centerName = org?.name ?? 'Centro';
  final brand = _parseHex(org?.brandPrimaryColor) ?? PdfColor.fromInt(0xFF2563EB);

  // Resolución de "quién" por id (staff o usuario).
  final staffById = {for (final s in repo.listStaff()) s.id: s.fullName};
  final userById = {for (final u in repo.listUsers()) u.id: u.fullName};
  String who(String? id) =>
      id == null ? '' : (staffById[id] ?? userById[id] ?? '');

  final doc = pw.Document();

  for (final p in patients) {
    final admission = repo.activeAdmission(p.id);
    final assessments = repo.listRiskAssessments(p.id);
    final lastBraden = assessments.isNotEmpty ? assessments.first : null;
    final comorbid = repo
        .listComorbidities(p.id)
        .where((c) => c.status == ComorbilidadEstado.presente)
        .map((c) => c.code.label)
        .toList();
    final diagnoses = repo.listDiagnoses(p.id);
    final compliance =
        repo.preventiveCompliance(p.id, organizationId: organizationId, now: ref);
    final actions = repo.listPreventiveActions(p.id);
    final adverse = repo.listAdverseEventsForPatient(p.id);
    final instructions = repo.caregiverInstructionsFor(p.id);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          // Encabezado con marca del centro.
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: brand, width: 2)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(centerName,
                    style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: brand)),
                pw.Text('Reporte de prevención de lesiones por presión (LPP)',
                    style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Generado: ${fmtDateTime.format(ref)}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // Datos del paciente.
          _kvGrid([
            ('Paciente', p.fullName),
            ('Expediente', p.folio),
            ('Edad', p.age != null ? '${p.age} años' : '—'),
            ('Sexo', p.sex ?? '—'),
          ]),
          pw.SizedBox(height: 12),

          // Internamiento.
          _section('Internamiento', brand),
          if (admission != null)
            _kvGrid([
              ('Ubicación', admission.locationLabel.isNotEmpty ? admission.locationLabel : '—'),
              ('Ingreso', fmtDate.format(admission.admittedAt)),
              ('Estatus', admission.dischargedAt == null ? 'Activo' : 'Egresado'),
            ])
          else
            _muted('Sin internamiento activo registrado.'),
          pw.SizedBox(height: 12),

          // Riesgo (Braden).
          _section('Riesgo (escala de Braden)', brand),
          if (lastBraden != null)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                    'Última valoración: ${lastBraden.bradenScore ?? '—'} '
                    '(${_bradenBand(lastBraden.bradenScore)}) · '
                    '${fmtDate.format(lastBraden.assessedAt)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (assessments.length > 1) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('Historial:',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ...assessments.take(6).map((a) => pw.Bullet(
                        text:
                            '${fmtDate.format(a.assessedAt)} — Braden ${a.bradenScore ?? '—'} '
                            '(${_bradenBand(a.bradenScore)})'
                            '${who(a.assessedBy).isNotEmpty ? ' · ${who(a.assessedBy)}' : ''}',
                        style: const pw.TextStyle(fontSize: 9),
                      )),
                ],
              ],
            )
          else
            _muted('Sin valoraciones de Braden registradas.'),
          pw.SizedBox(height: 12),

          // Comorbilidades y diagnósticos.
          _section('Comorbilidades y diagnósticos', brand),
          pw.Text('Comorbilidades presentes:',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
          if (comorbid.isNotEmpty)
            pw.Wrap(
              spacing: 6,
              runSpacing: 4,
              children: comorbid.map((c) => _chip(c)).toList(),
            )
          else
            _muted('Sin comorbilidades registradas.'),
          pw.SizedBox(height: 6),
          pw.Text('Diagnósticos (CIE-10):',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
          if (diagnoses.isNotEmpty)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: diagnoses
                  .map((d) => pw.Bullet(
                        text:
                            '${d.code} — ${d.name}${d.isPrimary ? ' (principal)' : ''}',
                        style: const pw.TextStyle(fontSize: 9),
                      ))
                  .toList(),
            )
          else
            _muted('Sin diagnósticos codificados.'),
          pw.SizedBox(height: 12),

          // Cumplimiento de prevención (rondas).
          _section('Cumplimiento de prevención (ventana actual)', brand),
          if (compliance.hasExpected) ...[
            pw.Text('Global: ${compliance.globalPct}% '
                '(${compliance.doneTotal}/${compliance.expectedTotal})',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            ...compliance.byType.map(_complianceRow),
          ] else
            _muted('Sin actividades preventivas esperadas en la ventana actual.'),
          pw.SizedBox(height: 12),

          // Bitácora operativa (acciones aplicadas + eventos adversos).
          _section('Bitácora de prevención', brand),
          if (actions.isNotEmpty)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: actions
                  .take(15)
                  .map((a) => pw.Bullet(
                        text:
                            '${fmtDateTime.format(a.appliedAt)} — ${a.actionLabel}'
                            '${who(a.appliedBy).isNotEmpty ? ' · ${who(a.appliedBy)}' : ''}',
                        style: const pw.TextStyle(fontSize: 9),
                      ))
                  .toList(),
            )
          else
            _muted('Sin actividades preventivas registradas.'),
          if (adverse.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Eventos adversos:',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
            ...adverse.map((e) => pw.Bullet(
                  text:
                      '${fmtDate.format(e.occurredAt)} — ${e.type} (${e.severity.label})',
                  style: const pw.TextStyle(fontSize: 9),
                )),
          ],
          pw.SizedBox(height: 12),

          // Indicaciones al cuidador.
          if (instructions != null && instructions.trim().isNotEmpty) ...[
            _section('Indicaciones para el cuidador', brand),
            pw.Text(instructions, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 12),
          ],

          pw.SizedBox(height: 8),
          pw.Text(
            'Documento de apoyo a la prevención de LPP. La información clínica es '
            'responsabilidad del personal tratante.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  await Printing.layoutPdf(onLayout: (format) => doc.save());
}

// ---------------------------------------------------------------------------
// Helpers de presentación.
// ---------------------------------------------------------------------------

String _bradenBand(int? s) {
  if (s == null) return 'sin valoración';
  if (s <= 12) return 'riesgo alto';
  if (s <= 17) return 'riesgo medio';
  return 'riesgo bajo';
}

PdfColor? _parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : PdfColor.fromInt(v);
}

pw.Widget _section(String title, PdfColor brand) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(title,
          style: pw.TextStyle(
              fontSize: 12, fontWeight: pw.FontWeight.bold, color: brand)),
    );

pw.Widget _muted(String text) => pw.Text(text,
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600));

pw.Widget _chip(String label) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
    );

pw.Widget _kvGrid(List<(String, String)> rows) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows
          .map((r) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 90,
                      child: pw.Text('${r.$1}:',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey700)),
                    ),
                    pw.Expanded(
                      child: pw.Text(r.$2,
                          style: const pw.TextStyle(fontSize: 10)),
                    ),
                  ],
                ),
              ))
          .toList(),
    );

pw.Widget _complianceRow(PreventiveComplianceType c) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(c.title, style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.Text('${c.done}/${c.expected} · ${c.pct}%',
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: c.pct >= 85
                      ? PdfColors.green700
                      : c.pct >= 60
                          ? PdfColors.orange700
                          : PdfColors.red700)),
        ],
      ),
    );
