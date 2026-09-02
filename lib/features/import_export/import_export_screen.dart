import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/kura_theme.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../services/data_repository.dart';
import '../../services/csv_download.dart';
import '../../models/consultation.dart' show VisitTypeLabel;

/// Interoperabilidad con eKare: importación del historial (pantalla dedicada
/// `/ekare-import`) y exportación CSV de mediciones.
class ImportExportScreen extends ConsumerStatefulWidget {
  const ImportExportScreen({super.key});

  @override
  ConsumerState<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends ConsumerState<ImportExportScreen> {
  Future<void> _exportMeasurementsCsv(DataRepository repo) async {
    final patients = repo.listAllPatients();
    final rows = <List<dynamic>>[
      ['folio_paciente', 'herida_id', 'etiologia', 'fecha', 'largo_cm', 'ancho_cm', 'area_cm2', 'profundidad_cm'],
    ];
    for (final p in patients) {
      final wounds = repo.listWoundsForPatient(p.id);
      for (final w in wounds) {
        final measurements = repo.listMeasurementsForWound(w.id);
        for (final m in measurements) {
          rows.add([
            p.folio,
            w.id,
            w.etiology.name,
            m.measuredAt.toIso8601String().substring(0, 10),
            m.lengthCm,
            m.widthCm,
            m.areaCm2,
            m.depthCm,
          ]);
        }
      }
    }
    final csv = const ListToCsvConverter().convert(rows);
    // rows.length - 1 = filas de datos (sin el encabezado).
    _showCsvDialog('Mediciones', 'mediciones.csv', csv, rows.length - 1,
        repo: repo, kind: 'csv_mediciones');
  }

  /// §3.2 del paquete de salida: una fila por CONSULTA (paciente, fecha, autor,
  /// y el contenido de la nota clínica — la etiología/diagnóstico y el plan viven
  /// en los campos narrativos, el modelo no tiene columnas discretas para ellos).
  /// Se incluyen borradores con la marca `es_borrador` para no ocultar nada; el
  /// alcance ya lo acota la RLS al centro activo del llamador.
  Future<void> _exportConsultationsCsv(DataRepository repo) async {
    final patients = repo.listAllPatients();
    final staffById = {for (final s in repo.listStaff()) s.id: s};
    final rows = <List<dynamic>>[
      [
        'folio_paciente', 'paciente', 'fecha', 'tipo_visita', 'autor', 'cedula',
        'especialidad', 'es_borrador', 'tipo_cuidado', 'procedimiento',
        'materiales_usados', 'evolucion', 'resumen',
      ],
    ];
    for (final p in patients) {
      final consultations = repo.listConsultationsForPatient(p.id)
        ..sort((a, b) => a.visitDate.compareTo(b.visitDate));
      for (final c in consultations) {
        final staff = staffById[c.staffId];
        final autor = (c.followUpSignedBy?.isNotEmpty ?? false)
            ? c.followUpSignedBy!
            : (staff?.fullName ?? '');
        rows.add([
          p.folio,
          p.fullName,
          c.visitDate.toIso8601String().substring(0, 10),
          c.visitType.label,
          autor,
          c.followUpSignedLicense ?? staff?.cedulaProfesional ?? '',
          c.followUpSignedSpecialty ?? staff?.especialidad ?? '',
          c.isDraft ? 'sí' : 'no',
          c.followUpCareType ?? '',
          c.followUpProcedureDesc ?? '',
          c.followUpMaterialsUsed ?? '',
          c.followUpEvolution ?? '',
          c.visitSummary ?? '',
        ]);
      }
    }
    final csv = const ListToCsvConverter().convert(rows);
    _showCsvDialog('Consultas', 'consultas.csv', csv, rows.length - 1,
        repo: repo, kind: 'csv_consultas');
  }

  /// Muestra el CSV generado con vista previa Y descarga real. Antes solo había
  /// "Cerrar" (§2.4): seleccionar y copiar miles de filas de un diálogo no es
  /// viable para una entrega. Usa el downloadCsv() que ya existe (web + io).
  void _showCsvDialog(String title, String filename, String csv, int dataRows,
      {required DataRepository repo, required String kind}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('$title · $dataRows registros'),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width < 560 ? double.maxFinite : 500,
          child: SingleChildScrollView(child: Text(csv)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cerrar')),
          FilledButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Descargar'),
            style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
            onPressed: () async {
              await downloadCsv(filename, csv);
              // Registro de divulgación (0101): DESPUÉS de entregar la descarga.
              final user = ref.read(sessionProvider).user;
              await repo.recordDataDisclosure(
                organizationId: user?.organizationId,
                actorId: user?.id,
                actorEmail: user?.email,
                kind: kind,
                recordCount: dataRows,
                patientCount: repo.listAllPatients().length,
                fileName: filename,
              );
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importación y exportación de expedientes'),
        actions: const [UserMenuButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Importar mediciones de otro expediente',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          'Carga el export de mediciones de otro expediente (uno o varios '
                          'CSV): crea pacientes, heridas y su historial de '
                          'mediciones. Omite pacientes que ya existan.',
                          style: TextStyle(
                              fontSize: 12,
                              color: KuraColors.darkText.withOpacity(0.6)),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Abrir importador'),
                          style: FilledButton.styleFrom(
                              backgroundColor: KuraColors.primary),
                          onPressed: () => context.push('/import-export/ekare'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Exportar mediciones a CSV',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          'Genera un archivo CSV con todas las mediciones seriadas registradas, '
                          'compatible con una migración hacia o desde otro expediente.',
                          style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<DataRepository>(
                          future: DataRepository.instance(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const SizedBox.shrink();
                            return OutlinedButton.icon(
                              icon: const Icon(Icons.download),
                              label: const Text('Exportar CSV'),
                              onPressed: () => _exportMeasurementsCsv(snapshot.data!),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // §3.2 del paquete de salida: exportación de CONSULTAS. Junto con
                // las mediciones cubre lo que hoy se entrega a mano al terminar
                // contrato. El alcance lo acota la RLS al centro activo.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Exportar consultas a CSV',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          'Una fila por consulta: paciente, fecha, autor y el '
                          'contenido de la nota clínica (tipo de cuidado, '
                          'procedimiento, evolución, resumen). Incluye borradores, '
                          'marcados como tales.',
                          style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<DataRepository>(
                          future: DataRepository.instance(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const SizedBox.shrink();
                            return OutlinedButton.icon(
                              icon: const Icon(Icons.download),
                              label: const Text('Exportar CSV'),
                              onPressed: () => _exportConsultationsCsv(snapshot.data!),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
