import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/kura_theme.dart';
import '../../services/data_repository.dart';

/// Config del ADMIN: qué escalas del módulo de hospitalización participan en el
/// protocolo del centro (0085). Las apagadas no se ofrecen en "Escalas a
/// realizar" aunque el triage las dispararía. Braden (tamizaje) siempre aplica y
/// no se lista aquí.
class ScaleTogglesScreen extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const ScaleTogglesScreen({
    super.key,
    required this.repo,
    required this.organizationId,
  });
  @override
  ConsumerState<ScaleTogglesScreen> createState() => _ScaleTogglesScreenState();
}

class _ScaleTogglesScreenState extends ConsumerState<ScaleTogglesScreen> {
  late Set<String> _enabled;
  bool _initialized = false;
  bool _saving = false;

  void _initFrom(List<String> allIds) {
    if (_initialized) return;
    final org = widget.repo.organizationById(widget.organizationId);
    final saved = org?.enabledScales;
    _enabled = saved == null ? allIds.toSet() : saved.toSet();
    _initialized = true;
  }

  Future<void> _save(List<String> allIds) async {
    if (widget.organizationId == null) return;
    setState(() => _saving = true);
    try {
      // Todas encendidas → null (semántica "todas", incluye futuras escalas).
      final all = _enabled.length == allIds.length &&
          allIds.every(_enabled.contains);
      await widget.repo
          .setEnabledScales(widget.organizationId!, all ? null : _enabled.toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Escalas del protocolo guardadas ✅')));
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
    final catalog = ref.watch(scaleApplicabilityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Escalas del protocolo')),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cat) {
          final scales = cat.scales;
          final allIds = [for (final s in scales) s.scaleId];
          _initFrom(allIds);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Text(
                'Elige qué escalas participan en el protocolo de tu centro. Las '
                'que apagues no se ofrecerán al valorar, aunque el triage las '
                'sugeriría. Braden (tamizaje) siempre aplica.',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _enabled = allIds.toSet()),
                    child: const Text('Todas'),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _enabled = {}),
                    child: const Text('Ninguna'),
                  ),
                ],
              ),
              for (final s in scales)
                SwitchListTile(
                  dense: true,
                  title: Text(s.label, style: const TextStyle(fontSize: 14)),
                  value: _enabled.contains(s.scaleId),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                            if (v) {
                              _enabled.add(s.scaleId);
                            } else {
                              _enabled.remove(s.scaleId);
                            }
                          }),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando…' : 'Guardar'),
                onPressed: _saving ? null : () => _save(allIds),
              ),
            ],
          );
        },
      ),
    );
  }
}
