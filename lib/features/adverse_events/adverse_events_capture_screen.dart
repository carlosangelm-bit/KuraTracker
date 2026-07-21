import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/adverse_event.dart';
import '../../models/app_user.dart';
import '../../services/data_repository.dart';
import 'adverse_events_screen.dart' show adverseSeverityColor;

/// Catálogo de tipos de evento adverso (Protocolo "Manejo de eventos
/// adversos"). "Otro" habilita un campo de texto libre.
const List<String> kAdverseEventTypes = [
  'Infección',
  'Dehiscencia',
  'Reacción a material/apósito',
  'Sangrado',
  'Caída',
  'Dolor no controlado',
  'Deterioro de la herida',
  'Otro',
];

/// Captura de un evento adverso, ligada al paciente y opcionalmente a la
/// herida/consulta donde se detectó. Clasificación por gravedad, checklist de
/// señales de alarma, acciones y evolución. Regla: severity=centinela avisa
/// del reporte obligatorio ≤24 h.
class AdverseEventsCaptureScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String? woundId;
  final String? consultationId;

  const AdverseEventsCaptureScreen({
    super.key,
    required this.patientId,
    this.woundId,
    this.consultationId,
  });

  @override
  ConsumerState<AdverseEventsCaptureScreen> createState() =>
      _AdverseEventsCaptureScreenState();
}

class _AdverseEventsCaptureScreenState
    extends ConsumerState<AdverseEventsCaptureScreen> {
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  DateTime _occurredAt = DateTime.now();
  String? _typeSelection; // valor de kAdverseEventTypes
  final _typeOtherCtrl = TextEditingController();
  AdverseEventSeverity? _severity;
  final Set<AdverseEventAlarmSign> _alarmSigns = {};
  final _descriptionCtrl = TextEditingController();
  final _actionsCtrl = TextEditingController();
  final _evolutionCtrl = TextEditingController();
  // Herida vinculada (opcional): la pasada por ruta o la elegida en el form.
  String? _woundId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _woundId = widget.woundId;
  }

  @override
  void dispose() {
    _typeOtherCtrl.dispose();
    _descriptionCtrl.dispose();
    _actionsCtrl.dispose();
    _evolutionCtrl.dispose();
    super.dispose();
  }

  bool get _isOtherType => _typeSelection == 'Otro';

  String get _resolvedType => _isOtherType
      ? _typeOtherCtrl.text.trim()
      : (_typeSelection ?? '').trim();

  bool get _canSave =>
      _severity != null && _resolvedType.isNotEmpty && !_saving;

  Future<void> _pickOccurredAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (!mounted) return;
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _occurredAt.hour,
        time?.minute ?? _occurredAt.minute,
      );
    });
  }

  Future<void> _save(SessionState session) async {
    setState(() => _saving = true);
    final repo = await DataRepository.instance();

    // Resolver staffId (patrón admin-clinico: el admin lo resuelve perezoso).
    var staffId = session.user?.staffId;
    if (staffId == null && session.user?.role == AppRole.admin) {
      staffId = await repo.ensureAdminStaffId(session.user!);
    }
    final organizationId = session.user?.organizationId;
    if (organizationId == null) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No se pudo resolver el centro (organización) de tu cuenta.')),
        );
      }
      return;
    }

    try {
      await repo.createAdverseEvent(
        organizationId: organizationId,
        patientId: widget.patientId,
        staffId: staffId,
        woundId: _woundId,
        consultationId: widget.consultationId,
        occurredAt: _occurredAt,
        type: _resolvedType,
        severity: _severity!,
        alarmSigns: _alarmSigns,
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        actionsTaken: _actionsCtrl.text.trim().isEmpty
            ? null
            : _actionsCtrl.text.trim(),
        evolution: _evolutionCtrl.text.trim().isEmpty
            ? null
            : _evolutionCtrl.text.trim(),
      );
      if (!mounted) return;
      final centinela = _severity == AdverseEventSeverity.centinela;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(centinela
              ? 'Evento centinela registrado. Recuerde reportar a la autoridad ≤24 h.'
              : 'Evento adverso registrado.'),
        ),
      );
      // Navegación declarativa (GoRouter), no Navigator.pop.
      context.go('/patients/${widget.patientId}/adverse-events');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el evento: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar evento adverso')),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final wounds = repo.listWoundsForPatient(widget.patientId);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ---- Fecha/hora de ocurrencia ----
              _sectionTitle(context, 'Fecha y hora del evento'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_dateFmt.format(_occurredAt)),
                onPressed: _pickOccurredAt,
              ),
              const SizedBox(height: 20),

              // ---- Tipo ----
              _sectionTitle(context, 'Tipo de evento'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kAdverseEventTypes.map((t) {
                  final selected = _typeSelection == t;
                  return ChoiceChip(
                    label: Text(t),
                    selected: selected,
                    selectedColor: KuraColors.primary.withOpacity(0.15),
                    onSelected: (_) => setState(() => _typeSelection = t),
                  );
                }).toList(),
              ),
              if (_isOtherType) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _typeOtherCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Especifique el tipo de evento',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 20),

              // ---- Gravedad ----
              _sectionTitle(context, 'Gravedad'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AdverseEventSeverity.values.map((s) {
                  final selected = _severity == s;
                  final color = adverseSeverityColor(s);
                  return ChoiceChip(
                    label: Text(s.label),
                    selected: selected,
                    selectedColor: color.withOpacity(0.18),
                    labelStyle: TextStyle(
                      color: selected ? color : null,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _severity = s),
                  );
                }).toList(),
              ),
              if (_severity == AdverseEventSeverity.centinela) ...[
                const SizedBox(height: 10),
                _CentinelaHint(),
              ],
              const SizedBox(height: 20),

              // ---- Señales de alarma ----
              _sectionTitle(context, 'Señales de alarma'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AdverseEventAlarmSign.values.map((sign) {
                  final selected = _alarmSigns.contains(sign);
                  return FilterChip(
                    label: Text(sign.label),
                    selected: selected,
                    selectedColor: KuraColors.danger.withOpacity(0.15),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _alarmSigns.add(sign);
                      } else {
                        _alarmSigns.remove(sign);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ---- Herida vinculada (opcional) ----
              if (wounds.isNotEmpty) ...[
                _sectionTitle(context, 'Herida relacionada (opcional)'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: _woundId,
                  decoration: const InputDecoration(
                    labelText: 'Herida',
                  ),
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

              // ---- Descripción / acciones / evolución ----
              _sectionTitle(context, 'Descripción'),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Describa el evento adverso',
                ),
              ),
              const SizedBox(height: 16),
              _sectionTitle(context, 'Acciones tomadas'),
              const SizedBox(height: 8),
              TextField(
                controller: _actionsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Manejo inmediato, interconsultas, referencias…',
                ),
              ),
              const SizedBox(height: 16),
              _sectionTitle(context, 'Evolución'),
              const SizedBox(height: 8),
              TextField(
                controller: _evolutionCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Evolución posterior del paciente/herida',
                ),
              ),
              const SizedBox(height: 28),

              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Guardar evento'),
                onPressed: _canSave ? () => _save(session) : null,
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );
}

class _CentinelaHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KuraColors.danger.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KuraColors.danger.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: KuraColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Evento centinela: requiere reporte a la autoridad (COFEPRIS) en ≤24 h. '
              'Aparecerá marcado como pendiente en la bitácora hasta registrarse el reporte.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: KuraColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
