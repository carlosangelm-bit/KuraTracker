import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/kura_theme.dart';
import '../../models/data_disclosure.dart';
import '../../services/data_repository.dart';

/// Registro de divulgaciones (0101): qué datos clínicos SALIERON del centro,
/// cuándo y por mano de quién. Solo lectura (la tabla es inmutable). Visible
/// para admin del centro y para master. Lista simple, orden descendente.
class DataDisclosuresScreen extends ConsumerStatefulWidget {
  const DataDisclosuresScreen({super.key});
  @override
  ConsumerState<DataDisclosuresScreen> createState() =>
      _DataDisclosuresScreenState();
}

class _DataDisclosuresScreenState extends ConsumerState<DataDisclosuresScreen> {
  bool _refreshed = false;
  final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  Future<void> _refresh(DataRepository repo) async {
    await repo.refreshDataDisclosures();
    if (mounted) setState(() => _refreshed = true);
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;
    // El master ve todas las que le devuelva la RLS; el admin, las de su centro.
    final orgFilter = (user?.isMaster ?? false) ? null : user?.organizationId;

    return Scaffold(
      appBar: AppBar(title: const Text('Registro de divulgaciones')),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          if (!_refreshed) {
            // Carga perezosa (no se hidratan al login).
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _refresh(repo));
            return const Center(child: CircularProgressIndicator());
          }
          final items = repo.listDataDisclosures(organizationId: orgFilter);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Constancia de cada salida de datos del centro (CSV, '
                        'expediente, entrega). Solo lectura.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualizar',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => _refresh(repo),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Sin divulgaciones registradas.'),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _tile(items[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(DataDisclosure d) {
    final counts = <String>[
      if (d.recordCount != null) '${d.recordCount} reg.',
      if ((d.patientCount ?? 0) > 0) '${d.patientCount} pac.',
      if ((d.photoCount ?? 0) > 0) '${d.photoCount} fotos',
      if ((d.missingCount ?? 0) > 0) '${d.missingCount} faltantes',
    ].join(' · ');
    return ListTile(
      leading: Icon(_iconFor(d.kind), color: KuraColors.primary),
      title: Text(d.kindLabel,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_fmt.format(d.occurredAt.toLocal())} · '
              '${d.actorEmail ?? d.actorId ?? 'desconocido'}'),
          if (counts.isNotEmpty)
            Text(counts,
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.7))),
          if (d.fileName != null)
            Text(d.fileName!,
                style: TextStyle(
                    fontSize: 11,
                    color: KuraColors.darkText.withValues(alpha: 0.55))),
        ],
      ),
      isThreeLine: true,
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'expediente_paciente':
        return Icons.folder_zip_outlined;
      case 'entrega_centro':
        return Icons.inventory_2_outlined;
      default:
        return Icons.table_view_outlined; // CSVs
    }
  }
}
