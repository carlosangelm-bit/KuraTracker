import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../services/acuity_service.dart';
import '../../services/data_repository.dart';

/// Config del tipo de cita de Acuity para las sesiones del plan (0080). El
/// master/admin elige, de la lista de Acuity, qué tipo representa una "sesión
/// de curación/seguimiento"; con ese tipo se agendan las sesiones al aceptar.
class AcuitySessionTypeScreen extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const AcuitySessionTypeScreen({
    super.key,
    required this.repo,
    required this.organizationId,
  });
  @override
  ConsumerState<AcuitySessionTypeScreen> createState() =>
      _AcuitySessionTypeScreenState();
}

class _AcuitySessionTypeScreenState
    extends ConsumerState<AcuitySessionTypeScreen> {
  late Future<List<dynamic>> _typesFuture;
  bool _saving = false;
  String? _selectedSiteId;

  @override
  void initState() {
    super.initState();
    final sites = widget.repo
        .listSites(organizationId: widget.organizationId)
        .where((s) => s.isActive)
        .toList();
    _selectedSiteId = sites.isEmpty ? null : sites.first.id;
    _typesFuture = ref.read(acuityServiceProvider).appointmentTypes();
  }

  int? get _current =>
      widget.repo.siteById(_selectedSiteId)?.acuitySessionTypeId;

  Future<void> _select(int typeId) async {
    if (_selectedSiteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Elige primero un sitio.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.setSiteAcuitySessionType(_selectedSiteId!, typeId);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tipo de cita configurado ✅')));
      }
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
      appBar: AppBar(title: const Text('Tipo de cita para sesiones')),
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
                child: Text('No se pudo cargar los tipos de Acuity.\n${snap.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final types = (snap.data ?? const []).whereType<Map>().toList();
          final sites = widget.repo
              .listSites(organizationId: widget.organizationId)
              .where((s) => s.isActive)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Text(
                'Elige el tipo de cita de Acuity con el que se agendarán las '
                'sesiones del plan de tratamiento. La configuración es POR '
                'SITIO; se usará al aceptar un plan para crear las citas del mes '
                'en Acuity.',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 12),
              // Selector de sitio del centro. Si hay más de uno, se configura
              // cada sitio por separado.
              if (sites.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Este centro no tiene sitios activos.',
                      style: TextStyle(
                          fontSize: 12, color: KuraColors.danger)),
                )
              else ...[
                DropdownButtonFormField<String>(
                  value: _selectedSiteId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Sitio', isDense: true),
                  items: [
                    for (final s in sites)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _selectedSiteId = v),
                ),
                const SizedBox(height: 8),
              ],
              if (types.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Acuity no devolvió tipos de cita.')),
                )
              else
                for (final t in types)
                  RadioListTile<int>(
                    value: (t['id'] as num).toInt(),
                    groupValue: _current,
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v != null) _select(v);
                          },
                    title: Text('${t['name'] ?? ''}'),
                    subtitle: Text([
                      if (t['duration'] != null) '${t['duration']} min',
                      if ('${t['category'] ?? ''}'.isNotEmpty) '${t['category']}',
                    ].join(' · ')),
                  ),
            ],
          );
        },
      ),
    );
  }
}
