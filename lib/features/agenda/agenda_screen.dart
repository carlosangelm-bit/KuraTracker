import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../models/appointment.dart';
import '../../services/acuity_service.dart';

/// Agenda de citas (Acuity Scheduling). El clínico ve SUS citas y el admin las
/// del centro (el aislamiento lo aplica la RLS de la tabla `appointments`).
/// Las altas/cambios pasan por la Edge Function `acuity-proxy`.
class AgendaScreen extends ConsumerWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(acuityServiceProvider);
    final user = ref.watch(sessionProvider).user;
    final isAdmin = user?.role == AppRole.admin;

    return Scaffold(
      appBar: AppBar(title: Text(isAdmin ? 'Agenda del centro' : 'Mi agenda')),
      body: !service.isAvailable
          ? const _AgendaUnavailable()
          : StreamBuilder<List<Appointment>>(
              stream: service.watchAppointments(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error al cargar la agenda: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final now = DateTime.now();
                final appointments = snapshot.data!
                    .where((a) => !a.isCanceled && (a.datetime?.isAfter(now) ?? false))
                    .toList();
                if (appointments.isEmpty) {
                  return const _AgendaEmpty();
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: appointments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _AppointmentTile(appointment: appointments[i], service: service),
                );
              },
            ),
      floatingActionButton: service.isAvailable
          ? FloatingActionButton.extended(
              backgroundColor: KuraColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.event_available),
              label: const Text('Nueva cita'),
              onPressed: () => _openScheduleSheet(context, service),
            )
          : null,
    );
  }
}

Future<void> _openScheduleSheet(
  BuildContext context,
  AcuityService service, {
  int? rescheduleId,
  int? presetTypeId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ScheduleSheet(
        service: service,
        rescheduleId: rescheduleId,
        presetTypeId: presetTypeId,
      ),
    ),
  );
}

class _AppointmentTile extends StatelessWidget {
  final Appointment appointment;
  final AcuityService service;
  const _AppointmentTile({required this.appointment, required this.service});

  @override
  Widget build(BuildContext context) {
    final dt = appointment.datetime;
    final dateStr = dt == null ? '—' : DateFormat('dd/MM/yyyy · HH:mm').format(dt);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: KuraColors.primary.withOpacity(0.12),
          child: const Icon(Icons.event, color: KuraColors.primary),
        ),
        title: Text(appointment.patientName.isEmpty ? 'Cita' : appointment.patientName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '$dateStr'
          '${appointment.appointmentType != null ? ' · ${appointment.appointmentType}' : ''}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'cancel') {
              await _confirmCancel(context, service, appointment);
            } else if (v == 'reschedule') {
              await _openScheduleSheet(context, service, rescheduleId: appointment.id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'reschedule', child: Text('Reagendar')),
            PopupMenuItem(value: 'cancel', child: Text('Cancelar cita')),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmCancel(
    BuildContext context, AcuityService service, Appointment a) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Cancelar cita'),
      content: Text('¿Cancelar la cita de ${a.patientName}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('No')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KuraColors.danger),
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: const Text('Cancelar cita'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await service.cancel(a.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cita cancelada.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo cancelar: $e')));
    }
  }
}

/// Flujo compacto: elegir tipo → fecha → hora (→ nombre/email si es alta nueva).
class _ScheduleSheet extends StatefulWidget {
  final AcuityService service;
  final int? rescheduleId;
  final int? presetTypeId;
  const _ScheduleSheet({required this.service, this.rescheduleId, this.presetTypeId});

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  bool _loading = true;
  String? _error;
  List<dynamic> _types = const [];
  int? _typeId;
  List<dynamic> _dates = const [];
  String? _date;
  List<dynamic> _times = const [];
  String? _time; // ISO datetime devuelto por Acuity
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;

  bool get _isReschedule => widget.rescheduleId != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      if (widget.presetTypeId != null) {
        _typeId = widget.presetTypeId;
        await _loadDates();
      } else {
        _types = await widget.service.appointmentTypes();
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadDates() async {
    final month = DateFormat('yyyy-MM').format(DateTime.now());
    _dates = await widget.service.availabilityDates(_typeId!, month);
    _date = null;
    _times = const [];
    _time = null;
  }

  Future<void> _loadTimes() async {
    _times = await widget.service.availabilityTimes(_typeId!, _date!);
    _time = null;
  }

  Future<void> _submit() async {
    if (_time == null) return;
    setState(() => _saving = true);
    try {
      if (_isReschedule) {
        await widget.service.reschedule(widget.rescheduleId!, _time!);
      } else {
        await widget.service.createAppointment(
          appointmentTypeID: _typeId!,
          datetime: _time!,
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          email: _email.text.trim(),
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isReschedule ? 'Cita reagendada.' : 'Cita creada.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _time != null &&
        (_isReschedule ||
            (_firstName.text.trim().isNotEmpty &&
                _lastName.text.trim().isNotEmpty &&
                _email.text.trim().isNotEmpty));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text('Error: $_error', style: const TextStyle(color: KuraColors.danger))
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_isReschedule ? 'Reagendar cita' : 'Nueva cita',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        if (!_isReschedule && widget.presetTypeId == null) ...[
                          const Text('Servicio', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            value: _typeId,
                            isExpanded: true,
                            items: [
                              for (final t in _types)
                                DropdownMenuItem<int>(
                                  value: (t['id'] as num).toInt(),
                                  child: Text('${t['name']}'),
                                ),
                            ],
                            onChanged: (v) async {
                              _typeId = v;
                              setState(() => _loading = true);
                              await _loadDates();
                              if (mounted) setState(() => _loading = false);
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_typeId != null) ...[
                          const Text('Fecha', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _date,
                            isExpanded: true,
                            hint: const Text('Selecciona una fecha con cupo'),
                            items: [
                              for (final d in _dates)
                                DropdownMenuItem<String>(
                                  value: '${d['date']}',
                                  child: Text('${d['date']}'),
                                ),
                            ],
                            onChanged: (v) async {
                              _date = v;
                              setState(() => _loading = true);
                              await _loadTimes();
                              if (mounted) setState(() => _loading = false);
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_date != null) ...[
                          const Text('Hora', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final t in _times)
                                ChoiceChip(
                                  label: Text(_fmtTime('${t['time']}')),
                                  selected: _time == '${t['time']}',
                                  onSelected: (_) => setState(() => _time = '${t['time']}'),
                                ),
                            ],
                          ),
                          if (_times.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('Sin horarios disponibles ese día.'),
                            ),
                          const SizedBox(height: 12),
                        ],
                        if (!_isReschedule && _time != null) ...[
                          TextField(
                            controller: _firstName,
                            decoration: const InputDecoration(labelText: 'Nombre'),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _lastName,
                            decoration: const InputDecoration(labelText: 'Apellido'),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email'),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                        ],
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
                          onPressed: (!canSubmit || _saving) ? null : _submit,
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(_isReschedule ? 'Reagendar' : 'Crear cita'),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  String _fmtTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    return dt == null ? iso : DateFormat('HH:mm').format(dt);
  }
}

class _AgendaUnavailable extends StatelessWidget {
  const _AgendaUnavailable();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined,
                size: 48, color: KuraColors.darkText.withOpacity(0.25)),
            const SizedBox(height: 12),
            const Text('Agenda no disponible en modo demo',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'La agenda se conecta con Acuity Scheduling a través de Supabase. '
              'Estará disponible al ejecutar la app con un proyecto Supabase '
              'configurado y las Edge Functions de Acuity desplegadas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: KuraColors.darkText.withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgendaEmpty extends StatelessWidget {
  const _AgendaEmpty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_outlined,
                size: 48, color: KuraColors.darkText.withOpacity(0.25)),
            const SizedBox(height: 12),
            Text('Sin citas próximas',
                style: TextStyle(color: KuraColors.darkText.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }
}
