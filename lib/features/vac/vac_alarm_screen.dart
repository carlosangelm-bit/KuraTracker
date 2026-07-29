import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../models/vac_alarm.dart';
import '../../models/vac_therapy.dart';
import '../../services/data_repository.dart';

/// Triage de alarmas de una terapia VAC (Fase 2). Elige la alarma → pasos
/// guiados según severidad. Las CRÍTICAS empujan a reinstalar + contactar a la
/// guardia (WhatsApp). Todo queda en la bitácora.
class VacAlarmScreen extends ConsumerStatefulWidget {
  final String therapyId;
  const VacAlarmScreen({super.key, required this.therapyId});
  @override
  ConsumerState<VacAlarmScreen> createState() => _VacAlarmScreenState();
}

class _VacAlarmScreenState extends ConsumerState<VacAlarmScreen> {
  VacAlarm? _selected;

  String? get _uid => ref.read(sessionProvider).user?.id;
  bool get _isAdmin =>
      ref.read(sessionProvider).user?.role == AppRole.admin;

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final t = BrandTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_selected != null) {
              setState(() => _selected = null);
            } else if (context.canPop()) {
              context.pop();
            } else {
              context.go('/vac/${widget.therapyId}');
            }
          },
        ),
        title: Text(_selected == null ? 'Atender alarma' : _selected!.label),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final therapy = repo.getVacTherapy(widget.therapyId);
          if (therapy == null) {
            return const Center(child: Text('Terapia no encontrada.'));
          }
          return _selected == null
              ? _alarmList(t, therapy)
              : _alarmSteps(t, repo, therapy, _selected!);
        },
      ),
    );
  }

  Widget _alarmList(BrandTokens t, VacTherapy therapy) {
    final alarms = VacAlarmCatalog.forEquipment(therapy.equipment);
    final criticas =
        alarms.where((a) => a.severity == VacAlarmSeverity.critica).toList();
    final noCrit =
        alarms.where((a) => a.severity == VacAlarmSeverity.noCritica).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Text('¿Qué alarma presenta el equipo? (${therapy.equipment.label})',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Contenido orientativo (borrador). No sustituye el juicio clínico.',
            style: TextStyle(fontSize: 12, color: t.textSecondary)),
        const SizedBox(height: 12),
        if (noCrit.isNotEmpty) ...[
          Text('Se pueden atender', style: TextStyle(color: t.textSecondary)),
          ...noCrit.map((a) => _alarmTile(t, a)),
          const SizedBox(height: 12),
        ],
        if (criticas.isNotEmpty) ...[
          Text('Críticas (requieren reinstalación)',
              style: TextStyle(color: t.statusDanger, fontWeight: FontWeight.w600)),
          ...criticas.map((a) => _alarmTile(t, a)),
        ],
      ],
    );
  }

  Widget _alarmTile(BrandTokens t, VacAlarm a) {
    final crit = a.severity == VacAlarmSeverity.critica;
    final color = crit ? t.statusDanger : t.statusWarning;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
            crit ? Icons.warning_amber_rounded : Icons.info_outline,
            color: color),
        title: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(a.severity.label,
            style: TextStyle(fontSize: 12, color: color)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => setState(() => _selected = a),
      ),
    );
  }

  Widget _alarmSteps(
      BrandTokens t, DataRepository repo, VacTherapy therapy, VacAlarm a) {
    final crit = a.severity == VacAlarmSeverity.critica;
    final color = crit ? t.statusDanger : t.statusWarning;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(crit ? Icons.warning_amber_rounded : Icons.info_outline,
                  color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  crit
                      ? 'Alarma CRÍTICA: requiere reinstalar la terapia. Contacta a la guardia.'
                      : 'Alarma no crítica: sigue estos pasos.',
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < a.steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: t.brandPrimary.withValues(alpha: 0.12),
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: t.brandPrimary)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(a.steps[i])),
              ],
            ),
          ),
        const SizedBox(height: 20),

        // Contactar guardia (WhatsApp).
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366)),
            icon: const Icon(Icons.chat),
            label: const Text('Contactar guardia (WhatsApp)'),
            onPressed: () => _escalate(repo, therapy, a),
          ),
        ),
        const SizedBox(height: 10),

        if (crit)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.build_outlined),
              label: const Text('Registrar reinstalación'),
              onPressed: () => _logAndBack(repo, therapy,
                  type: VacEventType.reinstalacion,
                  note: 'Reinstalación por alarma: ${a.label}',
                  msg: 'Reinstalación registrada.'),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Marcar resuelta'),
              onPressed: () => _logAndBack(repo, therapy,
                  type: VacEventType.alarma,
                  note: 'Alarma resuelta: ${a.label}',
                  msg: 'Alarma registrada como resuelta.'),
            ),
          ),
      ],
    );
  }

  Future<void> _logAndBack(DataRepository repo, VacTherapy therapy,
      {required VacEventType type,
      required String note,
      required String msg}) async {
    await repo.addVacEvent(
      organizationId: therapy.organizationId,
      therapyId: therapy.id,
      patientId: therapy.patientId,
      type: type,
      byProfile: _uid,
      note: note,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/vac/${therapy.id}');
    }
  }

  Future<void> _escalate(
      DataRepository repo, VacTherapy therapy, VacAlarm a) async {
    var phone = repo.vacOncallPhone(therapy.organizationId);
    if (phone == null) {
      if (!_isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'No hay número de guardia configurado. Pídele al administrador que lo capture.')));
        return;
      }
      phone = await _configurePhone(repo, therapy.organizationId);
      if (phone == null) return;
    }
    final patient = repo.getPatient(therapy.patientId);
    final msg = StringBuffer()
      ..writeln('Guardia VAC — alarma')
      ..writeln('Paciente: ${patient?.fullName ?? therapy.patientId}')
      ..writeln('Equipo: ${therapy.equipment.label}')
      ..writeln('Parámetros: ${therapy.settingsLabel}')
      ..writeln('Ubicación: ${therapy.currentLocation?.label ?? '—'}')
      ..writeln('Alarma: ${a.label} (${a.severity.label})');
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse(
        'https://wa.me/$digits?text=${Uri.encodeComponent(msg.toString())}');

    await repo.addVacEvent(
      organizationId: therapy.organizationId,
      therapyId: therapy.id,
      patientId: therapy.patientId,
      type: VacEventType.alarma,
      byProfile: _uid,
      note: 'Alarma escalada a guardia: ${a.label} (${a.severity.label})',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) setState(() {});
  }

  Future<String?> _configurePhone(
      DataRepository repo, String orgId) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Número de guardia VAC'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'WhatsApp con lada',
              hintText: 'p. ej. 52 55 1234 5678'),
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
    if (ok != true) return null;
    final phone = ctrl.text.trim();
    if (phone.isEmpty) return null;
    await repo.setVacOncallPhone(
        organizationId: orgId, phone: phone, updatedBy: _uid);
    return phone;
  }
}
