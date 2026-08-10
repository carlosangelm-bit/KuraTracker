import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../services/data_repository.dart';

/// Interoperabilidad con eKare: importación del historial (pantalla dedicada
/// `/ekare-import`) y exportación CSV de mediciones.
class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key});

  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
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
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Exportación CSV generada'),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width < 560 ? double.maxFinite : 500,
            child: SingleChildScrollView(child: Text(csv)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cerrar')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interoperabilidad eKare'),
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
                        const Text('Importar historial de mediciones (eKare)',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          'Carga el export de mediciones de eKare (uno o varios '
                          'CSV): crea pacientes, heridas y su historial de '
                          'mediciones. Omite pacientes que ya existan.',
                          style: TextStyle(
                              fontSize: 12,
                              color: KuraColors.darkText.withOpacity(0.6)),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Abrir importador de eKare'),
                          style: FilledButton.styleFrom(
                              backgroundColor: KuraColors.primary),
                          onPressed: () => context.push('/ekare-import'),
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
