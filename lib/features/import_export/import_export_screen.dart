import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';

import '../../core/theme/kura_theme.dart';
import '../../services/data_repository.dart';
import '../../engine/models/kura_engine_enums.dart';

/// Interoperabilidad con eKare (sección 3): importación CSV de pacientes
/// (con mapeo de campos configurable) y exportación CSV de mediciones.
class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key});

  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
  List<List<dynamic>>? _previewRows;
  String? _fileName;
  final Map<String, String> _fieldMapping = {
    'full_name': '',
    'folio': '',
    'birth_date': '',
    'sex': '',
  };

  Future<void> _pickCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    final content = String.fromCharCodes(bytes);
    final rows = const CsvToListConverter().convert(content, eol: '\n');
    setState(() {
      _fileName = result.files.first.name;
      _previewRows = rows.take(10).toList();
    });
  }

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
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Exportación CSV generada'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(child: Text(csv)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Interoperabilidad eKare')),
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
                        const Text('Importar CSV desde eKare',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          'Carga un archivo CSV de pacientes o mediciones exportado desde eKare. '
                          'Podrás mapear las columnas a los campos internos.',
                          style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file),
                          label: Text(_fileName ?? 'Seleccionar archivo CSV'),
                          onPressed: _pickCsv,
                        ),
                        if (_previewRows != null) ...[
                          const SizedBox(height: 16),
                          const Text('Vista previa (primeras filas):',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: (_previewRows!.first)
                                  .map((c) => DataColumn(label: Text('$c')))
                                  .toList(),
                              rows: _previewRows!
                                  .skip(1)
                                  .map((r) => DataRow(
                                        cells: r.map((c) => DataCell(Text('$c'))).toList(),
                                      ))
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text('Mapeo de campos (configurable):',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          ..._fieldMapping.keys.map((field) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    SizedBox(width: 140, child: Text(field)),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _fieldMapping[field]!.isEmpty
                                            ? null
                                            : _fieldMapping[field],
                                        items: (_previewRows!.first)
                                            .map((c) => DropdownMenuItem(
                                                  value: '$c',
                                                  child: Text('$c'),
                                                ))
                                            .toList(),
                                        onChanged: (v) =>
                                            setState(() => _fieldMapping[field] = v ?? ''),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('Importar con este mapeo'),
                            style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Importación registrada (demo). En producción se crea un import_batch auditable.'),
                                ),
                              );
                            },
                          ),
                        ],
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
                          'compatible con una migración total futura hacia/desde eKare.',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
