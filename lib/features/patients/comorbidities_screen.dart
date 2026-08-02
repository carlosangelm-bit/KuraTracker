import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/layout/responsive.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/app_user.dart';
import '../../services/data_repository.dart';
import 'comorbidity_selector.dart';

/// Gestión de comorbilidades (Antecedentes Personales Patológicos, APP) de un
/// paciente — Fase 1 de cumplimiento (NOM-004). Se pueden agregar/actualizar
/// con el tiempo; cada cambio queda fechado, atribuido al profesional y
/// auditado. No se borra: una comorbilidad que deja de aplicar se marca
/// "Negado".
class ComorbiditiesScreen extends ConsumerStatefulWidget {
  final String patientId;
  const ComorbiditiesScreen({super.key, required this.patientId});

  @override
  ConsumerState<ComorbiditiesScreen> createState() =>
      _ComorbiditiesScreenState();
}

class _ComorbiditiesScreenState extends ConsumerState<ComorbiditiesScreen> {
  Map<Comorbilidad, ComorbilidadEstado> _values = {};
  bool _loaded = false;
  bool _saving = false;

  void _loadIfNeeded(DataRepository repo) {
    if (_loaded) return;
    _loaded = true;
    _values = {
      for (final c in repo.listComorbidities(widget.patientId)) c.code: c.status,
    };
  }

  /// Guarda TODAS las comorbilidades capturadas de una sola vez y regresa al
  /// paciente. (Antes se guardaba callado por cada toque, sin confirmación.)
  Future<void> _saveAll() async {
    setState(() => _saving = true);
    final session = ref.read(sessionProvider);
    final repo = await DataRepository.instance();
    var staffId = session.user?.staffId;
    if (staffId == null && session.user?.role == AppRole.admin) {
      staffId = await repo.ensureAdminStaffId(session.user!);
    }
    try {
      for (final entry in _values.entries) {
        await repo.setComorbidity(
          patientId: widget.patientId,
          code: entry.key,
          status: entry.value,
          staffId: staffId,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comorbilidades guardadas.')));
      context.go('/patients/${widget.patientId}');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver al paciente',
          onPressed: () => context.go('/patients/${widget.patientId}'),
        ),
        title: const Text('Comorbilidades (APP)'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          _loadIfNeeded(repo);
          return PageMaxWidth(child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: KuraColors.chipBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Antecedentes personales patológicos. Se pueden actualizar en '
                  'cualquier momento; cada cambio queda fechado, firmado y '
                  'auditado. Una comorbilidad que deja de aplicar se marca '
                  '"Negado" (no se borra). Solo las "Presente" influyen en el '
                  'arquetipo del paciente.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              ComorbidityStatusSelector(
                values: _values,
                onChanged: (code, status) =>
                    setState(() => _values[code] = status),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_saving ? 'Guardando…' : 'Guardar comorbilidades'),
                  onPressed: _saving ? null : _saveAll,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ));
        },
      ),
    );
  }
}
