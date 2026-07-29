import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../models/vac_therapy.dart';
import '../../services/data_repository.dart';
import 'vac_therapy_form.dart';

/// Detalle de una terapia VAC (Fase 1): parámetros, indicaciones para el
/// cuidador, acciones (cambio de equipo/apósito, egreso, suspender, finalizar)
/// y bitácora de eventos. Alarmas/bot son fase posterior.
class VacTherapyDetailScreen extends ConsumerStatefulWidget {
  final String therapyId;
  const VacTherapyDetailScreen({super.key, required this.therapyId});
  @override
  ConsumerState<VacTherapyDetailScreen> createState() =>
      _VacTherapyDetailScreenState();
}

class _VacTherapyDetailScreenState
    extends ConsumerState<VacTherapyDetailScreen> {
  final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  String? get _uid => ref.read(sessionProvider).user?.id;

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final t = BrandTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/vac'),
        ),
        title: const Text('Terapia VAC'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final therapy = repo.getVacTherapy(widget.therapyId);
          if (therapy == null) {
            return const Center(child: Text('Terapia no encontrada.'));
          }
          final patient = repo.getPatient(therapy.patientId);
          final events = repo.listVacEvents(therapy.id);
          final active = therapy.isActive;
          final screenW = MediaQuery.of(context).size.width;
          final pad = screenW > 900 ? (screenW - 860) / 2 : 16.0;

          return ListView(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
            children: [
              // Paciente + estado.
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () =>
                          context.push('/patients/${therapy.patientId}'),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(patient?.fullName ?? 'Paciente',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: t.brandPrimary,
                                    decoration: TextDecoration.underline),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.open_in_new, size: 14, color: t.brandPrimary),
                        ],
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(therapy.status.label),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Parámetros.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(therapy.equipment.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                          if (active)
                            TextButton(
                              onPressed: () => _edit(repo, therapy),
                              child: const Text('Editar'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _row('Parámetros',
                          therapy.settingsLabel.isEmpty ? '—' : therapy.settingsLabel),
                      if (therapy.instillation)
                        _row('Instilación',
                            '${therapy.instillSolution ?? 'Sí'}${therapy.instillDwellMin != null ? ' · ${therapy.instillDwellMin} min' : ''}'),
                      if ((therapy.deviceSerial ?? '').isNotEmpty)
                        _row('N° de serie', therapy.deviceSerial!),
                      if (therapy.changeIntervalHours != null)
                        _row('Cambio de apósito',
                            'cada ${therapy.changeIntervalHours} h'),
                      _row('Ubicación actual',
                          therapy.currentLocation?.label ?? '—'),
                      _row('Colocada',
                          '${therapy.placedLocation?.label ?? '—'}'
                          '${therapy.placedAt != null ? ' · ${_fmt.format(therapy.placedAt!)}' : ''}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Indicaciones para el cuidador.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Indicaciones para el cuidador',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          if (active)
                            TextButton(
                              onPressed: () => _editCaregiver(repo, therapy),
                              child: const Text('Editar'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (therapy.caregiverInstructions ?? '').trim().isEmpty
                            ? 'Sin indicaciones. Deja qué vigilar del equipo y qué '
                                'hacer ante una alarma simple.'
                            : therapy.caregiverInstructions!,
                        style: TextStyle(fontSize: 13, color: t.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Atender alarma (triage + escalamiento a guardia).
              if (active) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Atender una alarma'),
                    onPressed: () =>
                        context.push('/vac/${therapy.id}/alarm'),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Acciones.
              if (active)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _action(Icons.swap_horiz, 'Cambiar equipo',
                        () => _changeEquipment(repo, therapy)),
                    _action(Icons.medication_outlined, 'Cambio de apósito',
                        () => _quickEvent(repo, therapy, VacEventType.cambioAposito,
                            'Cambio de apósito')),
                    _action(Icons.home_outlined, 'Egreso a domicilio',
                        () => _dischargeHome(repo, therapy)),
                    _action(Icons.pause_circle_outline, 'Suspender',
                        () => _setStatus(repo, therapy, VacTherapyStatus.suspendida,
                            VacEventType.suspension)),
                    _action(Icons.check_circle_outline, 'Finalizar',
                        () => _finish(repo, therapy)),
                    _action(Icons.note_add_outlined, 'Agregar nota',
                        () => _quickEvent(repo, therapy, VacEventType.nota, null,
                            askNote: true)),
                  ],
                )
              else if (therapy.status == VacTherapyStatus.suspendida)
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Reiniciar terapia'),
                  onPressed: () => _setStatus(
                      repo, therapy, VacTherapyStatus.activa, VacEventType.reinicio),
                ),
              const SizedBox(height: 20),

              // Bitácora.
              Text('Bitácora',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (events.isEmpty)
                const Text('Sin eventos.')
              else
                ...events.map((e) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.circle, size: 10, color: t.brandPrimary),
                        title: Text(e.type.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text([
                          _fmt.format(e.at),
                          if (e.location != null) e.location!.label,
                          if ((e.note ?? '').isNotEmpty) e.note!,
                        ].join(' · '), style: const TextStyle(fontSize: 12)),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 130,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: BrandTokens.of(context).textSecondary))),
            Expanded(
                child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  Widget _action(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label),
        onPressed: onTap,
      );

  // ---- Acciones ----

  Future<void> _edit(DataRepository repo, VacTherapy therapy) async {
    final ok = await showVacTherapyForm(context, ref,
        orgId: therapy.organizationId,
        patientId: therapy.patientId,
        existing: therapy);
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _editCaregiver(DataRepository repo, VacTherapy therapy) async {
    final ctrl =
        TextEditingController(text: therapy.caregiverInstructions ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Indicaciones para el cuidador'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
              hintText:
                  'Qué vigilar del equipo, alarmas simples, cuándo llamar…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (saved != true) return;
    await repo.updateVacTherapy(therapy.id,
        caregiverInstructions: ctrl.text.trim());
    if (mounted) setState(() {});
  }

  Future<void> _changeEquipment(DataRepository repo, VacTherapy therapy) async {
    var equipment = therapy.equipment == VacEquipment.vacUlta
        ? VacEquipment.activac
        : therapy.equipment;
    final serialCtrl = TextEditingController(text: therapy.deviceSerial ?? '');
    var location = therapy.currentLocation ?? VacLocation.hospital;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bctx) => StatefulBuilder(
        builder: (bctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 4,
              bottom: MediaQuery.of(bctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cambio de equipo',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              DropdownButtonFormField<VacEquipment>(
                value: equipment,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Nuevo equipo'),
                items: VacEquipment.values
                    .map((e) =>
                        DropdownMenuItem(value: e, child: Text(e.label)))
                    .toList(),
                onChanged: (v) => setSheet(() => equipment = v ?? equipment),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: serialCtrl,
                decoration:
                    const InputDecoration(labelText: 'N° de serie (opcional)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<VacLocation>(
                value: location,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ubicación'),
                items: VacLocation.values
                    .map((l) =>
                        DropdownMenuItem(value: l, child: Text(l.label)))
                    .toList(),
                onChanged: (v) => setSheet(() => location = v ?? location),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(bctx).pop(true),
                  child: const Text('Registrar cambio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    await repo.updateVacTherapy(therapy.id,
        equipment: equipment,
        deviceSerial: serialCtrl.text.trim(),
        currentLocation: location);
    await repo.addVacEvent(
      organizationId: therapy.organizationId,
      therapyId: therapy.id,
      patientId: therapy.patientId,
      type: VacEventType.cambioEquipo,
      location: location,
      byProfile: _uid,
      note: '${therapy.equipment.label} → ${equipment.label}',
    );
    if (mounted) setState(() {});
  }

  Future<void> _dischargeHome(DataRepository repo, VacTherapy therapy) async {
    final ok = await _confirm('Egreso a domicilio',
        'Registrar que la terapia se va a domicilio con el paciente.');
    if (!ok) return;
    await repo.updateVacTherapy(therapy.id,
        currentLocation: VacLocation.domicilio);
    await repo.addVacEvent(
      organizationId: therapy.organizationId,
      therapyId: therapy.id,
      patientId: therapy.patientId,
      type: VacEventType.egresoDomicilio,
      location: VacLocation.domicilio,
      byProfile: _uid,
    );
    if (mounted) setState(() {});
  }

  Future<void> _setStatus(DataRepository repo, VacTherapy therapy,
      VacTherapyStatus status, VacEventType eventType) async {
    await repo.updateVacTherapy(therapy.id, status: status);
    await repo.addVacEvent(
      organizationId: therapy.organizationId,
      therapyId: therapy.id,
      patientId: therapy.patientId,
      type: eventType,
      byProfile: _uid,
    );
    if (mounted) setState(() {});
  }

  Future<void> _finish(DataRepository repo, VacTherapy therapy) async {
    final ok = await _confirm('Finalizar terapia',
        'Marcar la terapia como finalizada. Ya no aparecerá en activas.');
    if (!ok) return;
    await repo.updateVacTherapy(therapy.id,
        status: VacTherapyStatus.finalizada, endedAt: DateTime.now());
    await repo.addVacEvent(
      organizationId: therapy.organizationId,
      therapyId: therapy.id,
      patientId: therapy.patientId,
      type: VacEventType.finalizacion,
      byProfile: _uid,
    );
    if (mounted) setState(() {});
  }

  Future<void> _quickEvent(DataRepository repo, VacTherapy therapy,
      VacEventType type, String? note,
      {bool askNote = false}) async {
    String? finalNote = note;
    if (askNote) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(type.label),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Nota…'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Agregar')),
          ],
        ),
      );
      if (ok != true) return;
      finalNote = ctrl.text.trim();
    }
    await repo.addVacEvent(
      organizationId: therapy.organizationId,
      therapyId: therapy.id,
      patientId: therapy.patientId,
      type: type,
      byProfile: _uid,
      note: finalNote,
    );
    if (mounted) setState(() {});
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    return r == true;
  }
}
