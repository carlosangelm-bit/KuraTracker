import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
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

  void _loadIfNeeded(DataRepository repo) {
    if (_loaded) return;
    _loaded = true;
    _values = {
      for (final c in repo.listComorbidities(widget.patientId)) c.code: c.status,
    };
  }

  Future<void> _setStatus(Comorbilidad code, ComorbilidadEstado status) async {
    final session = ref.read(sessionProvider);
    final repo = await DataRepository.instance();
    var staffId = session.user?.staffId;
    if (staffId == null && session.user?.role == AppRole.admin) {
      staffId = await repo.ensureAdminStaffId(session.user!);
    }
    await repo.setComorbidity(
      patientId: widget.patientId,
      code: code,
      status: status,
      staffId: staffId,
    );
    if (mounted) setState(() => _values[code] = status);
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
          return ListView(
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
                onChanged: _setStatus,
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}
