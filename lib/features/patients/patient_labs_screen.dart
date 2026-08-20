import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/widgets/kura_primary_fab.dart';
import '../../engine/labs/lab_domain_scoring.dart';
import '../../models/patient_lab.dart';
import '../../services/data_repository.dart';

/// Color de una severidad 0–3 del dominio clínico.
Color severityColor(LabSeverity s) => switch (s) {
      LabSeverity.normal => KuraColors.success,
      LabSeverity.mild => KuraColors.warning,
      LabSeverity.moderate => const Color(0xFFE8590C), // naranja intenso
      LabSeverity.severe => KuraColors.danger,
    };

/// Laboratorios del paciente (0070 + dominio clínico 0073). Los MÁS RECIENTES
/// alimentan el motor de cicatrización (albúmina); el resto del dominio se
/// puntúa 0–3 (informativo, banderas de severidad — ver lab_domain_scoring.dart).
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
                'El laboratorio más reciente alimenta el motor de cicatrización '
                '(albúmina). El dominio clínico completo se puntúa 0–3 por '
                'parámetro (banderas de severidad); los umbrales siguen en '
                'validación clínica.',
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
      floatingActionButton: KuraPrimaryFab(
        onPressed: () => _add(repoAsync.valueOrNull, user?.organizationId,
            user?.id),
        icon: Icons.add,
        label: 'Registrar labs',
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
    final summary = scoreClinicalDomain(lab);

    String fmtVal(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

    Widget paramChip(LabParamScore p) {
      final v = p.value!;
      final s = p.severity!;
      final c = severityColor(s);
      // Plaquetas: mostrar en miles para legibilidad (250,000 → 250k).
      final shown = p.key == 'platelets' && v >= 1000
          ? '${(v / 1000).toStringAsFixed(0)}k'
          : fmtVal(v);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: c.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              child: Text('${s.index}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            Text('${p.label}: $shown ${p.unit}',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    final worst = summary.worst;
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
                if (worst != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: severityColor(worst).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      summary.highCount > 0
                          ? 'Dominio: ${worst.label} · ${summary.highCount} en alto'
                          : 'Dominio: ${worst.label}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: severityColor(worst)),
                    ),
                  ),
                IconButton(
                  tooltip: 'Eliminar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (summary.isEmpty && (lab.o2SaturationPct == null))
              Text('Sin parámetros capturados.',
                  style: TextStyle(
                      fontSize: 12,
                      color: KuraColors.darkText.withOpacity(0.5)))
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final p in summary.measured) paramChip(p),
                  // SatO₂ es un signo vital (no está en el puntaje del dominio),
                  // pero se muestra junto para contexto.
                  if (lab.o2SaturationPct != null)
                    Chip(
                      label: Text('SatO₂: ${fmtVal(lab.o2SaturationPct!)} %',
                          style: TextStyle(
                              fontSize: 12,
                              color: lab.o2SaturationPct! < 90
                                  ? KuraColors.danger
                                  : null)),
                      backgroundColor: lab.o2SaturationPct! < 90
                          ? KuraColors.danger.withOpacity(0.10)
                          : KuraColors.chipBg,
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
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
  // Nutrición
  final _alb = TextEditingController();
  final _prealb = TextEditingController();
  final _prot = TextEditingController();
  // Metabólico
  final _glu = TextEditingController();
  final _hba1c = TextEditingController();
  // Hematología
  final _hb = TextEditingController();
  final _hct = TextEditingController();
  final _plt = TextEditingController();
  // Inflamación / coagulación
  final _crp = TextEditingController();
  final _pt = TextEditingController();
  final _ptt = TextEditingController();
  // Vital
  final _o2 = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _alb,
      _prealb,
      _prot,
      _glu,
      _hba1c,
      _hb,
      _hct,
      _plt,
      _crp,
      _pt,
      _ptt,
      _o2,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _n(TextEditingController c) => c.text.trim().isEmpty
      ? null
      : double.tryParse(c.text.trim().replaceAll(',', '.').replaceAll(' ', ''));

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
        prealbuminMgDl: _n(_prealb),
        totalProteinGdl: _n(_prot),
        crpMgL: _n(_crp),
        ptSeconds: _n(_pt),
        hematocritPct: _n(_hct),
        plateletsUl: _n(_plt),
        pttSeconds: _n(_ptt),
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

    // Campo numérico con vista previa de severidad 0–3 en vivo.
    Widget field(TextEditingController c, String label, String unit,
        LabSeverity? Function(double) sev) {
      final v = _n(c);
      final s = (v == null) ? null : sev(v);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            suffixText: unit,
            isDense: true,
            suffixIcon: s == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _sevDot(s),
                  ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
        ),
      );
    }

    Widget header(String t) => Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: KuraColors.primary)),
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
            const SizedBox(height: 4),
            Text(
              'Captura solo lo que tengas; cada parámetro muestra su severidad '
              '0–3. Los umbrales están en validación clínica.',
              style: TextStyle(
                  fontSize: 11, color: KuraColors.darkText.withOpacity(0.6)),
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 4),
            header('Nutrición'),
            field(_alb, 'Albúmina', 'g/dL', sevAlbumin),
            field(_prealb, 'Prealbúmina', 'mg/dL', sevPrealbumin),
            field(_prot, 'Proteínas totales', 'g/dL', sevTotalProtein),
            header('Metabólico (glucémico)'),
            field(_hba1c, 'HbA1c (si DM)', '%', sevHba1c),
            field(_glu, 'Glucosa', 'mg/dL', sevGlucose),
            header('Hematología'),
            field(_hb, 'Hemoglobina', 'g/dL', sevHemoglobin),
            field(_hct, 'Hematocrito', '%', sevHematocrit),
            field(_plt, 'Plaquetas', 'µL', sevPlatelets),
            header('Inflamación y coagulación'),
            field(_crp, 'PCR', 'mg/L', sevCrp),
            field(_pt, 'TP', 'seg', sevPt),
            field(_ptt, 'TPP', 'seg', sevPtt),
            header('Signo vital'),
            field(_o2, 'Saturación O₂', '%', (_) => null),
            const SizedBox(height: 4),
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

  Widget _sevDot(LabSeverity s) {
    final c = severityColor(s);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: Text('${s.index}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Text(s.label,
            style: TextStyle(
                fontSize: 11, color: c, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
