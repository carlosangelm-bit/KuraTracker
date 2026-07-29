import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../models/vac_therapy.dart';

/// Hoja para CREAR o EDITAR una terapia VAC. Devuelve `true` si se guardó.
/// Al crear registra la colocación; al editar registra un "ajuste" en bitácora.
Future<bool?> showVacTherapyForm(
  BuildContext context,
  WidgetRef ref, {
  required String orgId,
  required String patientId,
  VacTherapy? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VacTherapyForm(
      orgId: orgId,
      patientId: patientId,
      existing: existing,
    ),
  );
}

class _VacTherapyForm extends ConsumerStatefulWidget {
  final String orgId;
  final String patientId;
  final VacTherapy? existing;
  const _VacTherapyForm({
    required this.orgId,
    required this.patientId,
    this.existing,
  });
  @override
  ConsumerState<_VacTherapyForm> createState() => _VacTherapyFormState();
}

class _VacTherapyFormState extends ConsumerState<_VacTherapyForm> {
  late VacEquipment _equipment;
  late VacMode? _mode;
  late VacDressing? _dressing;
  late VacLocation? _placedLocation;
  late bool _instillation;
  late final TextEditingController _serialCtrl;
  late final TextEditingController _pressureCtrl;
  late final TextEditingController _intervalCtrl;
  late final TextEditingController _solutionCtrl;
  late final TextEditingController _dwellCtrl;
  late final TextEditingController _caregiverCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _equipment = e?.equipment ?? VacEquipment.vacUlta;
    _mode = e?.mode;
    _dressing = e?.dressing;
    _placedLocation = e?.placedLocation ?? VacLocation.quirofano;
    _instillation = e?.instillation ?? false;
    _serialCtrl = TextEditingController(text: e?.deviceSerial ?? '');
    _pressureCtrl =
        TextEditingController(text: e?.targetPressureMmhg?.toString() ?? '125');
    _intervalCtrl =
        TextEditingController(text: e?.changeIntervalHours?.toString() ?? '48');
    _solutionCtrl = TextEditingController(text: e?.instillSolution ?? '');
    _dwellCtrl =
        TextEditingController(text: e?.instillDwellMin?.toString() ?? '');
    _caregiverCtrl = TextEditingController(text: e?.caregiverInstructions ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _pressureCtrl.dispose();
    _intervalCtrl.dispose();
    _solutionCtrl.dispose();
    _dwellCtrl.dispose();
    _caregiverCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    if (repo == null) {
      setState(() => _saving = false);
      return;
    }
    final uid = ref.read(sessionProvider).user?.id;
    final pressure = int.tryParse(_pressureCtrl.text.trim());
    final interval = int.tryParse(_intervalCtrl.text.trim());
    final dwell = int.tryParse(_dwellCtrl.text.trim());
    final serial = _serialCtrl.text.trim();
    final solution = _solutionCtrl.text.trim();
    final caregiver = _caregiverCtrl.text.trim();
    final notes = _notesCtrl.text.trim();
    try {
      if (_isEdit) {
        await repo.updateVacTherapy(
          widget.existing!.id,
          equipment: _equipment,
          deviceSerial: serial,
          mode: _mode,
          targetPressureMmhg: pressure,
          instillation: _instillation,
          instillSolution: solution,
          instillDwellMin: dwell,
          dressing: _dressing,
          changeIntervalHours: interval,
          caregiverInstructions: caregiver,
          notes: notes,
        );
        await repo.addVacEvent(
          organizationId: widget.orgId,
          therapyId: widget.existing!.id,
          patientId: widget.patientId,
          type: VacEventType.ajuste,
          byProfile: uid,
          note: 'Ajuste de parámetros',
        );
      } else {
        await repo.createVacTherapy(
          organizationId: widget.orgId,
          patientId: widget.patientId,
          equipment: _equipment,
          deviceSerial: serial.isEmpty ? null : serial,
          mode: _mode,
          targetPressureMmhg: pressure,
          instillation: _instillation,
          instillSolution: solution.isEmpty ? null : solution,
          instillDwellMin: dwell,
          dressing: _dressing,
          changeIntervalHours: interval,
          placedLocation: _placedLocation,
          caregiverInstructions: caregiver.isEmpty ? null : caregiver,
          notes: notes.isEmpty ? null : notes,
          createdBy: uid,
        );
      }
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
            Text(_isEdit ? 'Editar terapia VAC' : 'Nueva terapia VAC',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            DropdownButtonFormField<VacEquipment>(
              value: _equipment,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Equipo'),
              items: VacEquipment.values
                  .map((e) =>
                      DropdownMenuItem(value: e, child: Text(e.label)))
                  .toList(),
              onChanged: (v) => setState(() => _equipment = v ?? _equipment),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _serialCtrl,
              decoration: const InputDecoration(
                  labelText: 'N° de serie del equipo (opcional)'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<VacMode?>(
              value: _mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Modo'),
              items: [
                const DropdownMenuItem<VacMode?>(
                    value: null, child: Text('Sin especificar')),
                ...VacMode.values.map((m) =>
                    DropdownMenuItem<VacMode?>(value: m, child: Text(m.label))),
              ],
              onChanged: (v) => setState(() => _mode = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pressureCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Presión (mmHg)', prefixText: '-'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _intervalCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Cambio c/ (h)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<VacDressing?>(
              value: _dressing,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Apósito / interfaz'),
              items: [
                const DropdownMenuItem<VacDressing?>(
                    value: null, child: Text('Sin especificar')),
                ...VacDressing.values.map((d) => DropdownMenuItem<VacDressing?>(
                    value: d, child: Text(d.label))),
              ],
              onChanged: (v) => setState(() => _dressing = v),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<VacLocation?>(
                value: _placedLocation,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Lugar de colocación'),
                items: VacLocation.values
                    .map((l) => DropdownMenuItem<VacLocation?>(
                        value: l, child: Text(l.label)))
                    .toList(),
                onChanged: (v) => setState(() => _placedLocation = v),
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Con instilación (Veraflo)'),
              value: _instillation,
              onChanged: (v) => setState(() => _instillation = v),
            ),
            if (_instillation) ...[
              TextField(
                controller: _solutionCtrl,
                decoration:
                    const InputDecoration(labelText: 'Solución de instilación'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dwellCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Tiempo de permanencia (min)'),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _caregiverCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Indicaciones de funcionamiento para el cuidador',
                hintText:
                    'Qué vigilar del equipo, qué hacer ante una alarma simple…',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? 'Guardando…'
                    : (_isEdit ? 'Guardar cambios' : 'Registrar terapia')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
