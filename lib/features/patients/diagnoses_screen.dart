import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/cie10_catalog.dart';
import '../../models/app_user.dart';
import '../../models/patient_diagnosis.dart';
import '../../services/data_repository.dart';
import 'cie10_picker_sheet.dart';

/// Gestión de diagnósticos CIE-10 del expediente (NOM-004). El clínico busca en
/// el catálogo, agrega diagnósticos con su relación frente a la herida
/// (causa/comorbilidad/consecuencia/herida), marca el principal y cambia su
/// estado. Cada cambio queda fechado, atribuido y auditado. No se borra: un dx
/// que deja de aplicar se marca "Descartado"/"Resuelto".
///
/// Alcance DOCUMENTAL: no alimenta el motor Kura+ (eso son las comorbilidades).
class DiagnosesScreen extends ConsumerStatefulWidget {
  final String patientId;
  const DiagnosesScreen({super.key, required this.patientId});

  @override
  ConsumerState<DiagnosesScreen> createState() => _DiagnosesScreenState();
}

class _DiagnosesScreenState extends ConsumerState<DiagnosesScreen> {
  Future<String?> _resolveStaffId(DataRepository repo) async {
    final session = ref.read(sessionProvider);
    var staffId = session.user?.staffId;
    if (staffId == null && session.user?.role == AppRole.admin) {
      staffId = await repo.ensureAdminStaffId(session.user!);
    }
    return staffId;
  }

  Future<void> _addDiagnosis(DataRepository repo, Cie10Catalog catalog) async {
    final code = await showCie10PickerSheet(context, catalog);
    if (code == null || !mounted) return;
    // Segundo paso: confirmar relación (prellenada del catálogo), principal y
    // notas antes de registrar.
    final detail = await _showAddDetailSheet(code);
    if (detail == null || !mounted) return;

    final session = ref.read(sessionProvider);
    final staffId = await _resolveStaffId(repo);
    await repo.addDiagnosis(
      patientId: widget.patientId,
      code: code,
      relation: detail.relation,
      isPrimary: detail.primary,
      notes: detail.notes,
      organizationId: session.user?.organizationId,
      staffId: staffId,
    );
    if (mounted) setState(() {});
  }

  Future<_AddDetail?> _showAddDetailSheet(Cie10Code code) {
    var relation = code.relation;
    var primary = false;
    final notesCtrl = TextEditingController();
    return showModalBottomSheet<_AddDetail>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${code.code} · ${code.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              DropdownButtonFormField<DiagnosisRelation>(
                value: relation,
                decoration: const InputDecoration(
                  labelText: 'Relación con la herida',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final r in DiagnosisRelation.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) => setSheet(() => relation = v ?? relation),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Diagnóstico principal'),
                subtitle: const Text('Reemplaza al principal anterior'),
                value: primary,
                onChanged: (v) => setSheet(() => primary = v),
              ),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Agregar diagnóstico'),
                  onPressed: () => Navigator.of(context).pop(_AddDetail(
                    relation: relation,
                    primary: primary,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setStatus(
      DataRepository repo, PatientDiagnosis d, DiagnosisStatus status) async {
    final staffId = await _resolveStaffId(repo);
    await repo.setDiagnosisStatus(
        diagnosisId: d.id, status: status, staffId: staffId);
    if (mounted) setState(() {});
  }

  Future<void> _setPrimary(DataRepository repo, PatientDiagnosis d) async {
    await repo.setPrimaryDiagnosis(widget.patientId, d.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final catalogAsync = ref.watch(cie10CatalogProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver al paciente',
          onPressed: () => context.go('/patients/${widget.patientId}'),
        ),
        title: const Text('Diagnósticos (CIE-10)'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) => catalogAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error al cargar catálogo: $e')),
          data: (catalog) {
            final diagnoses = repo.listDiagnoses(widget.patientId);
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
                    'Diagnósticos codificados (CIE-10) del expediente. Se pueden '
                    'actualizar en cualquier momento; cada cambio queda fechado, '
                    'firmado y auditado. Un diagnóstico que deja de aplicar se '
                    'marca "Resuelto" o "Descartado" (no se borra). Es registro '
                    'documental: no modifica el motor Kura+.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar diagnóstico'),
                    onPressed: () => _addDiagnosis(repo, catalog),
                  ),
                ),
                const SizedBox(height: 16),
                if (diagnoses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Sin diagnósticos registrados.'),
                  )
                else
                  ...diagnoses.map((d) => _DiagnosisTile(
                        diagnosis: d,
                        onStatus: (s) => _setStatus(repo, d, s),
                        onPrimary: () => _setPrimary(repo, d),
                      )),
                const SizedBox(height: 40),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AddDetail {
  final DiagnosisRelation relation;
  final bool primary;
  final String? notes;
  const _AddDetail({required this.relation, required this.primary, this.notes});
}

Color _statusColor(DiagnosisStatus s) {
  switch (s) {
    case DiagnosisStatus.activo:
      return KuraColors.success;
    case DiagnosisStatus.resuelto:
      return KuraColors.infoBlue;
    case DiagnosisStatus.descartado:
      return KuraColors.darkText;
  }
}

class _DiagnosisTile extends StatelessWidget {
  final PatientDiagnosis diagnosis;
  final void Function(DiagnosisStatus) onStatus;
  final VoidCallback onPrimary;
  const _DiagnosisTile({
    required this.diagnosis,
    required this.onStatus,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final d = diagnosis;
    final relColor = diagnosisRelationColor(d.relation);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: Icon(Icons.circle, size: 10, color: relColor),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${d.code} · ${d.name}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(d.relation.label,
                          style: TextStyle(fontSize: 11, color: relColor)),
                      if (d.notes != null && d.notes!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(d.notes!,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) {
                    if (value == 'primary') {
                      onPrimary();
                    } else {
                      onStatus(DiagnosisStatusX.fromDb(value));
                    }
                  },
                  itemBuilder: (context) => [
                    if (!d.isPrimary && d.status == DiagnosisStatus.activo)
                      const PopupMenuItem(
                          value: 'primary',
                          child: Text('Marcar como principal')),
                    for (final s in DiagnosisStatus.values)
                      if (s != d.status)
                        PopupMenuItem(
                            value: s.dbValue, child: Text('Marcar ${s.label.toLowerCase()}')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                if (d.isPrimary)
                  const Chip(
                    label: Text('Principal', style: TextStyle(fontSize: 11)),
                    avatar: Icon(Icons.star, size: 12, color: KuraColors.primary),
                    backgroundColor: KuraColors.chipBg,
                    visualDensity: VisualDensity.compact,
                  ),
                Chip(
                  label: Text(d.status.label, style: const TextStyle(fontSize: 11)),
                  avatar: Icon(Icons.circle, size: 10, color: _statusColor(d.status)),
                  backgroundColor: KuraColors.chipBg,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
