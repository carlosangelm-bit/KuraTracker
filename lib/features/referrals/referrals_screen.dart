import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/referral.dart';
import '../../services/data_repository.dart';
import '../../services/referral_pdf.dart';

/// Bitácora de referencias/interconsultas de un paciente (Prompt 6): lista,
/// regeneración del PDF y captura del documento de retorno del especialista.
class ReferralsScreen extends ConsumerStatefulWidget {
  final String patientId;
  const ReferralsScreen({super.key, required this.patientId});

  @override
  ConsumerState<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends ConsumerState<ReferralsScreen> {
  final _dateFmt = DateFormat('dd/MM/yyyy');

  Future<void> _regeneratePdf(Referral r) async {
    final repo = await DataRepository.instance();
    final patient = repo.getPatient(widget.patientId);
    if (patient == null) return;
    final staff = r.staffId == null ? null : repo.getStaff(r.staffId!);
    final orgId = ref.read(sessionProvider).user?.organizationId;
    final org = orgId == null
        ? null
        : repo.listOrganizations().where((o) => o.id == orgId).firstOrNull;
    await generateAndShowReferralPdf(
      referral: r,
      patient: patient,
      referringStaff: staff,
      org: org,
    );
  }

  Future<void> _registerReturn(Referral r) async {
    final result = await showDialog<_ReturnResult>(
      context: context,
      builder: (_) => const _RegisterReturnDialog(),
    );
    if (result == null) return;
    final repo = await DataRepository.instance();
    await repo.registerReferralReturn(
      r.id,
      returnDocRef: result.docRef,
      returnNotes: result.notes,
    );
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Respuesta del especialista registrada.')),
      );
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
        title: const Text('Referencias / interconsultas'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add_circle_outline, color: KuraColors.primary),
            label: const Text('Nueva referencia',
                style: TextStyle(color: KuraColors.primary)),
            onPressed: () =>
                context.go('/patients/${widget.patientId}/referrals/new'),
          ),
        ],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final referrals = repo.listReferralsForPatient(widget.patientId);
          if (referrals.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('Sin referencias registradas para este paciente.'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ...referrals.map((r) => _ReferralCard(
                    referral: r,
                    dateFmt: _dateFmt,
                    onRegeneratePdf: () => _regeneratePdf(r),
                    onRegisterReturn: () => _registerReturn(r),
                  )),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  final Referral referral;
  final DateFormat dateFmt;
  final VoidCallback onRegeneratePdf;
  final VoidCallback onRegisterReturn;

  const _ReferralCard({
    required this.referral,
    required this.dateFmt,
    required this.onRegeneratePdf,
    required this.onRegisterReturn,
  });

  @override
  Widget build(BuildContext context) {
    final adjuntos = referral.adjuntos.map((a) => a.label).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(referral.especialidad,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                _StatusChip(referral: referral),
              ],
            ),
            const SizedBox(height: 4),
            Text('Enviada: ${dateFmt.format(referral.createdAt.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(referral.motivo, style: Theme.of(context).textTheme.bodyMedium),
            if (adjuntos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: adjuntos
                    .map((label) => Chip(
                          label: Text(label),
                          backgroundColor: KuraColors.chipBg,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
            // Documento de retorno del especialista.
            if (referral.isRespondida) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KuraColors.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.assignment_turned_in,
                            size: 16, color: KuraColors.success),
                        const SizedBox(width: 6),
                        Text(
                          'Respondida el ${dateFmt.format(referral.returnedAt!.toLocal())}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                    if ((referral.returnDocRef ?? '').isNotEmpty)
                      Text('Documento: ${referral.returnDocRef}',
                          style: Theme.of(context).textTheme.bodySmall),
                    if ((referral.returnNotes ?? '').isNotEmpty)
                      Text(referral.returnNotes!,
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('PDF'),
                  onPressed: onRegeneratePdf,
                ),
                const Spacer(),
                if (!referral.isRespondida)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.reply, size: 18),
                    label: const Text('Registrar respuesta'),
                    onPressed: onRegisterReturn,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Referral referral;
  const _StatusChip({required this.referral});

  @override
  Widget build(BuildContext context) {
    final color = referral.isRespondida ? KuraColors.success : KuraColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(referral.status.label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class _ReturnResult {
  final String? docRef;
  final String? notes;
  _ReturnResult(this.docRef, this.notes);
}

class _RegisterReturnDialog extends StatefulWidget {
  const _RegisterReturnDialog();

  @override
  State<_RegisterReturnDialog> createState() => _RegisterReturnDialogState();
}

class _RegisterReturnDialogState extends State<_RegisterReturnDialog> {
  final _docRefCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _docRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar respuesta del especialista'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _docRefCtrl,
            decoration: const InputDecoration(
              labelText: 'Referencia del documento',
              hintText: 'Folio, archivo escaneado o URL',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Resumen de la respuesta',
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
            _ReturnResult(
              _docRefCtrl.text.trim().isEmpty ? null : _docRefCtrl.text.trim(),
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            ),
          ),
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
