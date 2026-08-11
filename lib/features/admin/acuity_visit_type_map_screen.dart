import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../services/acuity_service.dart';
import '../../services/data_repository.dart';

/// Config del mapeo tipo de cita de Acuity → tipo de consulta Kura (0083). El
/// admin/master elige, por cada tipo del catálogo de Acuity, si equivale a una
/// VALORACIÓN o a un SEGUIMIENTO. Con esto la consulta iniciada desde una cita
/// decide su tipo sola, y la consulta directa en KuraTracker usa este catálogo.
class AcuityVisitTypeMapScreen extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const AcuityVisitTypeMapScreen({
    super.key,
    required this.repo,
    required this.organizationId,
  });
  @override
  ConsumerState<AcuityVisitTypeMapScreen> createState() =>
      _AcuityVisitTypeMapScreenState();
}

class _AcuityVisitTypeMapScreenState
    extends ConsumerState<AcuityVisitTypeMapScreen> {
  late Future<List<dynamic>> _typesFuture;
  final Map<String, String> _map = {}; // nombre de tipo → 'valoracion'|'seguimiento'
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final org = widget.repo.organizationById(widget.organizationId);
    _map.addAll(org?.acuityTypeVisitMap ?? const {});
    _typesFuture = ref.read(acuityServiceProvider).appointmentTypes();
  }

  Future<void> _set(String name, String? visit) async {
    setState(() {
      if (visit == null) {
        _map.remove(name);
      } else {
        _map[name] = visit;
      }
      _saving = true;
    });
    try {
      await widget.repo
          .setAcuityTypeVisitMap(widget.organizationId!, Map.of(_map));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tipos de consulta (Acuity)')),
      body: FutureBuilder<List<dynamic>>(
        future: _typesFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                    'No se pudo cargar los tipos de Acuity.\n${snap.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final types = (snap.data ?? const []).whereType<Map>().toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Text(
                'Por cada tipo de cita de Acuity, elige si equivale a una '
                'VALORACIÓN o a un SEGUIMIENTO. Con esto: al iniciar una consulta '
                'desde una cita, el sistema decide el tipo solo; y al crear una '
                'consulta directa en KuraTracker, el usuario elige un tipo de este '
                'catálogo. Los tipos sin mapear seguirán preguntando el tipo.',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 12),
              if (types.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Acuity no devolvió tipos de cita.')),
                )
              else
                for (final t in types) _typeRow(t),
            ],
          );
        },
      ),
    );
  }

  Widget _typeRow(Map t) {
    final name = '${t['name'] ?? ''}';
    final sub = [
      if (t['duration'] != null) '${t['duration']} min',
      if ('${t['category'] ?? ''}'.isNotEmpty) '${t['category']}',
    ].join(' · ');
    final current = _map[name];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (sub.isNotEmpty)
              Text(sub,
                  style: TextStyle(
                      fontSize: 11,
                      color: KuraColors.darkText.withValues(alpha: 0.5))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Valoración'),
                  selected: current == 'valoracion',
                  onSelected: _saving
                      ? null
                      : (sel) => _set(name, sel ? 'valoracion' : null),
                ),
                ChoiceChip(
                  label: const Text('Seguimiento'),
                  selected: current == 'seguimiento',
                  onSelected: _saving
                      ? null
                      : (sel) => _set(name, sel ? 'seguimiento' : null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
