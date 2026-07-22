import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/consent.dart';
import '../../services/data_repository.dart';

/// Pantalla de gestión de consentimientos informados de un paciente
/// (Protocolos "Expedientes clínicos" y "Desbridamiento"). Permite otorgar o
/// revocar cada tipo (privacidad / fotografía / desbridamiento), registrando
/// quién firma y la referencia del documento.
class ConsentsScreen extends ConsumerStatefulWidget {
  final String patientId;
  const ConsentsScreen({super.key, required this.patientId});

  @override
  ConsumerState<ConsentsScreen> createState() => _ConsentsScreenState();
}

class _ConsentsScreenState extends ConsumerState<ConsentsScreen> {
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  Future<void> _grant(ConsentType type) async {
    final result = await showDialog<_GrantResult>(
      context: context,
      builder: (_) => _GrantConsentDialog(type: type),
    );
    if (result == null) return;
    final repo = await DataRepository.instance();
    await repo.setConsent(
      patientId: widget.patientId,
      type: type,
      granted: true,
      signedBy: result.signedBy,
      docRef: result.docRef,
    );
    if (mounted) setState(() {});
  }

  Future<void> _revoke(ConsentType type) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revocar consentimiento'),
        content: Text('¿Revocar el consentimiento de "${type.label}"? '
            'Esto puede bloquear la valoración, fotografía o desbridamiento.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Revocar')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await DataRepository.instance();
    await repo.setConsent(
        patientId: widget.patientId, type: type, granted: false);
    if (mounted) setState(() {});
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
        title: const Text('Consentimientos'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Registra el consentimiento informado del paciente. La '
                'valoración y la fotografía requieren privacidad + fotografía; '
                'el desbridamiento requiere su propio consentimiento, que debe '
                'firmarse ANTES del primer desbridamiento.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ...ConsentType.values.map((type) {
                final consent = repo.consentFor(widget.patientId, type);
                final granted = consent?.granted ?? false;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              granted
                                  ? Icons.check_circle
                                  : Icons.cancel_outlined,
                              color: granted
                                  ? KuraColors.success
                                  : KuraColors.danger,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(type.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                            ),
                            if (granted)
                              TextButton(
                                onPressed: () => _revoke(type),
                                child: const Text('Revocar'),
                              )
                            else
                              FilledButton.tonal(
                                onPressed: () => _grant(type),
                                child: const Text('Registrar'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(type.description,
                            style: Theme.of(context).textTheme.bodySmall),
                        if (granted && consent != null) ...[
                          const SizedBox(height: 8),
                          if (consent.grantedAt != null)
                            Text(
                                'Otorgado: ${_dateFmt.format(consent.grantedAt!.toLocal())}',
                                style: Theme.of(context).textTheme.bodySmall),
                          if ((consent.signedBy ?? '').isNotEmpty)
                            Text('Firma: ${consent.signedBy}',
                                style: Theme.of(context).textTheme.bodySmall),
                          if ((consent.docRef ?? '').isNotEmpty)
                            Text('Documento: ${consent.docRef}',
                                style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

class _GrantResult {
  final String? signedBy;
  final String? docRef;
  _GrantResult(this.signedBy, this.docRef);
}

class _GrantConsentDialog extends StatefulWidget {
  final ConsentType type;
  const _GrantConsentDialog({required this.type});

  @override
  State<_GrantConsentDialog> createState() => _GrantConsentDialogState();
}

class _GrantConsentDialogState extends State<_GrantConsentDialog> {
  final _signedByCtrl = TextEditingController();
  final _docRefCtrl = TextEditingController();

  @override
  void dispose() {
    _signedByCtrl.dispose();
    _docRefCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Registrar: ${widget.type.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.type.description,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _signedByCtrl,
            decoration: const InputDecoration(
              labelText: 'Firma / nombre de quien otorga',
              hintText: 'Paciente, tutor o representante',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _docRefCtrl,
            decoration: const InputDecoration(
              labelText: 'Referencia de documento (opcional)',
              hintText: 'Folio, archivo escaneado, etc.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _GrantResult(
              _signedByCtrl.text.trim().isEmpty ? null : _signedByCtrl.text.trim(),
              _docRefCtrl.text.trim().isEmpty ? null : _docRefCtrl.text.trim(),
            ),
          ),
          child: const Text('Otorgar consentimiento'),
        ),
      ],
    );
  }
}

/// Banner reutilizable de prerequisito de consentimientos. Muestra un aviso
/// claro (rojo) cuando faltan consentimientos requeridos, con acceso directo a
/// la pantalla de consentimientos del paciente. Devuelve un widget vacío
/// cuando todos los requeridos están otorgados.
class ConsentGateBanner extends StatelessWidget {
  final String patientId;
  final DataRepository repo;
  final List<ConsentType> required;

  /// Texto que explica qué acción está condicionada (p.ej. "la valoración y la
  /// toma de fotografía").
  final String actionLabel;

  const ConsentGateBanner({
    super.key,
    required this.patientId,
    required this.repo,
    required this.required,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final missing = repo.missingConsents(patientId, required);
    if (missing.isEmpty) return const SizedBox.shrink();
    final names = missing.map((t) => t.label).join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KuraColors.danger.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KuraColors.danger.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.gpp_maybe_outlined, color: KuraColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Consentimiento requerido: $actionLabel requiere registrar '
                  '$names.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: KuraColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
              label: const Text('Registrar consentimientos'),
              onPressed: () => context.go('/patients/$patientId/consents'),
            ),
          ),
        ],
      ),
    );
  }
}
