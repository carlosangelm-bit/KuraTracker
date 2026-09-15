import 'package:flutter/material.dart';
import '../../core/widgets/kura_back_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/kura_theme.dart';
import '../../core/widgets/kura_error_state.dart';
import '../../services/data_repository.dart';

/// Config del ADMIN: qué escalas del módulo de hospitalización participan en el
/// protocolo del centro (0085). Las apagadas no se ofrecen en "Escalas a
/// realizar" aunque el triage las dispararía. Braden (tamizaje) siempre aplica y
/// no se lista aquí.
///
/// Guarda AL INSTANTE (como sus hermanas): cada cambio persiste solo, sin botón
/// "Guardar" que se pueda perder al salir.
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

  void _initFrom(List<String> allIds) {
    if (_initialized) return;
    final org = widget.repo.organizationById(widget.organizationId);
    final saved = org?.enabledScales;
    _enabled = saved == null ? allIds.toSet() : saved.toSet();
    _initialized = true;
  }

  /// Persiste al instante el estado actual. Todas encendidas → null (semántica
  /// "todas", incluye futuras escalas).
  Future<void> _persist(List<String> allIds) async {
    if (widget.organizationId == null) return;
    final all =
        _enabled.length == allIds.length && allIds.every(_enabled.contains);
    try {
      await widget.repo
          .setEnabledScales(widget.organizationId!, all ? null : _enabled.toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
  }

  void _set(List<String> allIds, void Function() mutate) {
    setState(mutate);
    _persist(allIds);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(scaleApplicabilityProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const KuraBackButton(fallback: '/admin/configuracion'),
        title: const Text('Escalas del protocolo'),
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: KuraErrorState(
              title: 'No pudimos cargar las escalas',
              reassurance:
                  'Puede ser tu conexión. Tu configuración está a salvo: no se '
                  'perdió ni se guardó a medias.',
              detail: '$e',
              onRetry: () => ref.invalidate(scaleApplicabilityProvider),
            ),
          ),
        ),
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
                'sugeriría. Braden (tamizaje) siempre aplica. Los cambios se '
                'guardan solos.',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () =>
                        _set(allIds, () => _enabled = allIds.toSet()),
                    child: const Text('Todas'),
                  ),
                  TextButton(
                    onPressed: () => _set(allIds, () => _enabled = {}),
                    child: const Text('Ninguna'),
                  ),
                ],
              ),
              for (final s in scales)
                SwitchListTile(
                  dense: true,
                  title: Text(s.label, style: const TextStyle(fontSize: 14)),
                  value: _enabled.contains(s.scaleId),
                  onChanged: (v) => _set(allIds, () {
                    if (v) {
                      _enabled.add(s.scaleId);
                    } else {
                      _enabled.remove(s.scaleId);
                    }
                  }),
                ),
            ],
          );
        },
      ),
    );
  }
}
