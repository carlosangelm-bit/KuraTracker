import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/organization.dart';
import '../models/patient.dart';
import '../models/referral.dart';
import '../models/staff.dart';

/// Genera y muestra (Printing.layoutPdf) el "Formato de referencia /
/// interconsulta" (Prompt 6) con los datos del paciente, motivo, especialidad,
/// firma del profesional y el checklist de adjuntos.
Future<void> generateAndShowReferralPdf({
  required Referral referral,
  required Patient patient,
  StaffMember? referringStaff,
  Organization? org,
}) async {
  final dateFmt = DateFormat('dd/MM/yyyy');
  final brand = _brandColor(org?.brandPrimaryColor);
  final centerName = org?.name ?? 'KuraTracker';
  final firmaNombre =
      referral.referralSignedBy ?? referringStaff?.fullName ?? '—';
  final firmaCedula =
      referral.referralSignedLicense ?? referringStaff?.cedulaProfesional;

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Encabezado
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: brand, width: 4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(centerName,
                    style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: brand)),
                pw.Text(
                    'Formato de referencia / interconsulta · ${dateFmt.format(referral.createdAt)}',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Datos del paciente
          _sectionTitle('Datos del paciente', brand),
          _kv('Nombre', patient.fullName),
          _kv('Folio', patient.folio),
          if (patient.age != null) _kv('Edad', '${patient.age} años'),
          if ((patient.sex ?? '').isNotEmpty) _kv('Sexo', patient.sex!),
          if ((patient.ekareExternalId ?? '').isNotEmpty)
            _kv('eKare ID', patient.ekareExternalId!),
          pw.SizedBox(height: 12),

          // Referencia
          _sectionTitle('Referencia', brand),
          _kv('Especialidad', referral.especialidad),
          _kv('Motivo', referral.motivo),
          pw.SizedBox(height: 12),

          // Checklist de adjuntos
          _sectionTitle('Adjuntos', brand),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: ReferralAdjunto.values.map((a) {
              final incluido = referral.adjuntos.contains(a);
              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1),
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 10,
                      height: 10,
                      margin: const pw.EdgeInsets.only(right: 6),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey600),
                        color: incluido ? brand : PdfColors.white,
                      ),
                    ),
                    pw.Text(a.label, style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              );
            }).toList(),
          ),
          pw.SizedBox(height: 30),

          // Firma
          _sectionTitle('Profesional que refiere', brand),
          pw.SizedBox(height: 18),
          pw.Container(width: 220, decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey700)),
          )),
          pw.Text(firmaNombre,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          if (firmaCedula != null && firmaCedula.isNotEmpty)
            pw.Text('Cédula profesional: $firmaCedula',
                style: const pw.TextStyle(fontSize: 9)),

          pw.Spacer(),
          pw.Text(
            'Documento generado por KuraTracker. La respuesta del especialista '
            'se adjunta al expediente del paciente.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    ),
  );

  await Printing.layoutPdf(onLayout: (format) => doc.save());
}

pw.Widget _sectionTitle(String text, PdfColor brand) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 11, fontWeight: pw.FontWeight.bold, color: brand)),
    );

pw.Widget _kv(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text('$k:',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: 10))),
        ],
      ),
    );

PdfColor _brandColor(String? hex) {
  if (hex == null || hex.trim().isEmpty) return const PdfColor.fromInt(0xFF7C3AED);
  var h = hex.trim().replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? const PdfColor.fromInt(0xFF7C3AED) : PdfColor.fromInt(v);
}
