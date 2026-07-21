import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/app_user.dart';
import '../../models/referral.dart';
import '../../services/data_repository.dart';
import '../../services/referral_pdf.dart';

/// Alta de una referencia/interconsulta (Prompt 6): especialidad, motivo,
/// checklist de adjuntos, y generación del formato en PDF.
class ReferralCreateScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String? woundId;
  final String? consultationId;

  const ReferralCreateScreen({
    super.key,
    required this.patientId,
    this.woundId,
    this.consultationId,
  });

  @override
  ConsumerState<ReferralCreateScreen> createState() =>
      _ReferralCreateScreenState();
}

class _ReferralCreateScreenState extends ConsumerState<ReferralCreateScreen> {
  final _especialidadCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();
  final Set<ReferralAdjunto> _adjuntos = {};
  String? _woundId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _woundId = widget.woundId;
  }

  @override
  void dispose() {
    _especialidadCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _especialidadCtrl.text.trim().isNotEmpty &&
      _motivoCtrl.text.trim().isNotEmpty &&
      !_saving;

  Future<void> _save(SessionState session, {required bool generatePdf}) async {
    setState(() => _saving = true);
    final repo = await DataRepository.instance();
    var staffId = session.user?.staffId;
    if (staffId == null && session.user?.role == AppRole.admin) {
      staffId = await repo.ensureAdminStaffId(session.user!);
    }
    final staff = staffId == null ? null : repo.getStaff(staffId);

    try {
      final referral = await repo.createReferral(
        patientId: widget.patientId,
        staffId: staffId,
        woundId: _woundId,
        consultationId: widget.consultationId,
        especialidad: _especialidadCtrl.text.trim(),
        motivo: _motivoCtrl.text.trim(),
        adjuntos: _adjuntos,
        referralSignedBy: session.user?.fullName,
        referralSignedLicense: staff?.cedulaProfesional,
      );

      if (generatePdf) {
        final patient = repo.getPatient(widget.patientId);
        final orgId = session.user?.organizationId;
        final org = orgId == null
            ? null
            : repo.listOrganizations().where((o) => o.id == orgId).firstOrNull;
        if (patient != null) {
          await generateAndShowReferralPdf(
            referral: referral,
            patient: patient,
            referringStaff: staff,
            org: org,
          );
        }
      }
      if (!mounted) return;
      context.go('/patients/${widget.patientId}/referrals');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la referencia: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver a referencias',
          onPressed: () =>
              context.go('/patients/${widget.patientId}/referrals'),
        ),
        title: const Text('Nueva referencia'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final wounds = repo.listWoundsForPatient(widget.patientId);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _title(context, 'Especialidad'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kReferralEspecialidades.map((e) {
                  return ActionChip(
                    label: Text(e),
                    backgroundColor: _especialidadCtrl.text == e
                        ? KuraColors.primary.withOpacity(0.18)
                        : null,
                    onPressed: () =>
                        setState(() => _especialidadCtrl.text = e),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _especialidadCtrl,
                decoration: const InputDecoration(
                  labelText: 'Especialidad destino *',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              _title(context, 'Motivo de la referencia'),
              const SizedBox(height: 8),
              TextField(
                controller: _motivoCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Motivo clínico de la interconsulta',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              if (wounds.isNotEmpty) ...[
                _title(context, 'Herida relacionada (opcional)'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: _woundId,
                  decoration: const InputDecoration(labelText: 'Herida'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Ninguna / no aplica'),
                    ),
                    ...wounds.map((w) => DropdownMenuItem<String?>(
                          value: w.id,
                          child: Text(
                              '${w.etiology.label} — ${w.bodyLocationPrimary}'),
                        )),
                  ],
                  onChanged: (v) => setState(() => _woundId = v),
                ),
                const SizedBox(height: 20),
              ],

              _title(context, 'Checklist de adjuntos'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReferralAdjunto.values.map((a) {
                  final selected = _adjuntos.contains(a);
                  return FilterChip(
                    label: Text(a.label),
                    selected: selected,
                    selectedColor: KuraColors.primary.withOpacity(0.15),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _adjuntos.add(a);
                      } else {
                        _adjuntos.remove(a);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),

              FilledButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Guardar y generar PDF'),
                onPressed:
                    _canSave ? () => _save(session, generatePdf: true) : null,
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed:
                    _canSave ? () => _save(session, generatePdf: false) : null,
                child: const Text('Guardar sin generar'),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _title(BuildContext context, String t) => Text(
        t,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
