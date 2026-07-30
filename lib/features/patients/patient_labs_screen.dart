import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/patient_lab.dart';
import '../../services/data_repository.dart';

/// Laboratorios del paciente (0070). Los MÁS RECIENTES alimentan el motor de
/// cicatrización (albúmina, glucosa, saturación de O2).
class PatientLabsScreen extends ConsumerStatefulWidget {
  final String patientId;
  const PatientLabsScreen({super.key, required this.patientId});
  @override
  ConsumerState<PatientLabsScreen> createState() => _PatientLabsScreenState();
}

class _PatientLabsScreenState extends ConsumerState<PatientLabsScreen> {
  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/patients/${widget.patientId}'),
        ),
        title: const Text('Laboratorios'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final labs = repo.listPatientLabs(widget.patientId);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              Text(
                'Los laboratorios más recientes se usan en el motor de '
                'cicatrización (albúmina, glucosa, saturación de O₂). Los umbrales '
                'y su peso siguen en validación clínica.',
                style: TextStyle(
                    fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
              ),
              const SizedBox(height: 12),
              if (labs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Sin laboratorios registrados.')),
                )
              else
                ...labs.map((l) => _LabCard(
                      lab: l,
                      fmt: _fmt,
                      onDelete: () async {
                        await repo.deletePatientLab(l.id);
                        if (mounted) setState(() {});
                      },
                    )),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(repoAsync.valueOrNull, user?.organizationId,
            user?.id),
        icon: const Icon(Icons.add),
        label: const Text('Registrar labs'),
      ),
    );
  }

  Future<void> _add(
      DataRepository? repo, String? orgId, String? uid) async {
    if (repo == null || orgId == null) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LabForm(
        repo: repo,
        patientId: widget.patientId,
        orgId: orgId,
        createdBy: uid,
      ),
    );
    if (ok == true && mounted) setState(() {});
  }
}

class _LabCard extends StatelessWidget {
  final PatientLab lab;
  final DateFormat fmt;
  final Future<void> Function() onDelete;
  const _LabCard(
      {required this.lab, required this.fmt, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, double? v, String unit, {bool alert = false}) {
      if (v == null) return const SizedBox.shrink();
      return Chip(
        label: Text('$label: ${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} $unit',
            style: TextStyle(
                fontSize: 12, color: alert ? KuraColors.danger : null)),
        backgroundColor:
            alert ? KuraColors.danger.withOpacity(0.10) : KuraColors.chipBg,
        side: BorderSide.none,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(fmt.format(lab.takenAt),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDelete,
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                chip('Glucosa', lab.glucoseMgDl, 'mg/dL',
                    alert: (lab.glucoseMgDl ?? 0) > 180),
                chip('HbA1c', lab.hba1cPct, '%'),
                chip('Albúmina', lab.albuminGdl, 'g/dL',
                    alert: (lab.albuminGdl != null && lab.albuminGdl! < 3.0)),
                chip('Hb', lab.hemoglobinGdl, 'g/dL'),
                chip('SatO₂', lab.o2SaturationPct, '%',
                    alert: (lab.o2SaturationPct != null &&
                        lab.o2SaturationPct! < 90)),
              ],
            ),
            if ((lab.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(lab.notes!, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _LabForm extends StatefulWidget {
  final DataRepository repo;
  final String patientId;
  final String orgId;
  final String? createdBy;
  const _LabForm({
    required this.repo,
    required this.patientId,
    required this.orgId,
    required this.createdBy,
  });
  @override
  State<_LabForm> createState() => _LabFormState();
}

class _LabFormState extends State<_LabForm> {
  DateTime _date = DateTime.now();
  final _glu = TextEditingController();
  final _hba1c = TextEditingController();
  final _alb = TextEditingController();
  final _hb = TextEditingController();
  final _o2 = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _glu.dispose();
    _hba1c.dispose();
    _alb.dispose();
    _hb.dispose();
    _o2.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? _n(TextEditingController c) =>
      c.text.trim().isEmpty ? null : double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repo.addPatientLab(
        organizationId: widget.orgId,
        patientId: widget.patientId,
        takenAt: _date,
        glucoseMgDl: _n(_glu),
        hba1cPct: _n(_hba1c),
        albuminGdl: _n(_alb),
        hemoglobinGdl: _n(_hb),
        o2SaturationPct: _n(_o2),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        createdBy: widget.createdBy,
      );
      if (mounted) Navigator.of(context).pop(true);
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
    final fmt = DateFormat('dd/MM/yyyy');
    Widget field(TextEditingController c, String label, String unit) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: label, suffixText: unit, isDense: true),
          ),
        );
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Registrar laboratorios',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.event, size: 18),
                const SizedBox(width: 8),
                Text('Fecha: ${fmt.format(_date)}'),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: const Text('Cambiar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            field(_glu, 'Glucosa', 'mg/dL'),
            field(_hba1c, 'HbA1c', '%'),
            field(_alb, 'Albúmina', 'g/dL'),
            field(_hb, 'Hemoglobina', 'g/dL'),
            field(_o2, 'Saturación O₂', '%'),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Guardando…' : 'Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
