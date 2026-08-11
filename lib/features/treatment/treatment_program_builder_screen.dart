import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/inventory.dart';
import '../../models/note_option_catalog.dart';
import '../../models/protocol_product_rule.dart';
import '../../models/supply_product_mapping.dart';
import '../../models/appointment.dart';
import 'week_scheduler.dart';
import '../../models/treatment_program.dart';
import '../../services/acuity_service.dart';
import '../../services/data_repository.dart';

/// Renglón de insumo del plan en construcción. [perMonth] elige cómo se
/// interpreta [qty]: por sesión (default) o mensual directo (multidosis).
class _SupplyRow {
  final String method; // procedimiento
  final String? product; // genérico del régimen
  final String? inventoryItemId;
  final String name;
  final double? unitCost;
  final double? unitPrice;
  final String? currency;
  double qty = 1;
  bool perMonth = false; // true = qty ya es la cantidad del mes (multidosis)
  _SupplyRow({
    required this.method,
    this.product,
    this.inventoryItemId,
    required this.name,
    this.unitCost,
    this.unitPrice,
    this.currency,
  });
  double get unitAmount => unitPrice ?? unitCost ?? 0;
}

const _kWeekdayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D']; // 1..7

/// Capa intermedia tras la VALORACIÓN: arma el plan de tratamiento del mes.
/// Insumos por procedimiento (cantidad por sesión), cadencia (días + hora) y
/// sesiones del mes; valida empalmes contra Acuity (en rojo) y muestra la
/// explosión de materiales mensual.
class TreatmentProgramBuilderScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String woundId;
  final String consultationId;
  const TreatmentProgramBuilderScreen({
    super.key,
    required this.patientId,
    required this.woundId,
    required this.consultationId,
  });
  @override
  ConsumerState<TreatmentProgramBuilderScreen> createState() =>
      _TreatmentProgramBuilderScreenState();
}

class _TreatmentProgramBuilderScreenState
    extends ConsumerState<TreatmentProgramBuilderScreen> {
  // Formateo manual en español (el locale 'es' no está inicializado en la app).
  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  String _fmtDay(DateTime d) =>
      '${_dias[d.weekday - 1]} ${d.day} ${_meses[d.month - 1]}';
  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _money(double v) => '\$${v.toStringAsFixed(2)} MXN';

  bool _loading = true;
  bool _saving = false;
  String? _orgId;
  String? _siteId;
  String? _staffId;
  bool _acuityMode = false;

  final List<_SupplyRow> _supplies = [];

  // Cadencia
  final Set<int> _weekdays = {1, 3, 5}; // Lun/Mié/Vie por defecto
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  int _weeks = 4;
  late DateTime _startDate;
  // Modo de cadencia (0088): false = días de la semana; true = cada N horas.
  bool _hourlyMode = false;
  int _intervalHours = 72; // 24/48/72/96…
  int _sessionCount = 8; // nº de sesiones en modo horas
  static const List<int> _kIntervalPresets = [24, 48, 72, 96];

  List<Appointment> _acuityAppts = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  DataRepository? get _repo => ref.read(dataRepositoryProvider).valueOrNull;

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    final user = ref.read(sessionProvider).user;
    final patient = repo.getPatient(widget.patientId);
    final orgId = patient?.organizationId ?? user?.organizationId;
    _orgId = orgId;
    _staffId = user?.staffId;
    if (orgId != null) {
      final sites =
          repo.listSites(organizationId: orgId).where((s) => s.isActive).toList();
      _siteId = sites.isEmpty ? null : sites.first.id;
      _acuityMode = repo.schedulingModeFor(orgId) == 'acuity';
      _buildSuggestedSupplies(repo, orgId, _siteId);
    }
    await _refreshConflicts();
    if (mounted) setState(() => _loading = false);
  }

  void _buildSuggestedSupplies(DataRepository repo, String orgId, String? siteId) {
    _supplies.clear();
    final components = repo.treatmentComponentsForConsultation(widget.consultationId);

    // 1) Vía preferente (0076): resolución por CATEGORÍA + MEDIDA de la herida.
    final categories = <KuraTag>{
      for (final comp in components)
        if (kKuraMethodToTag[comp.method] != null) kKuraMethodToTag[comp.method]!
    };
    final measures = repo.listMeasurementsForWound(widget.woundId);
    final last = measures.isEmpty ? null : measures.last;
    final wound = repo.getWound(widget.woundId);
    // Exudado / infección salen de la valoración de ESTA consulta (o la última).
    final assessments = repo.listAssessmentsForWound(widget.woundId);
    final assess = assessments
            .where((a) => a.consultationId == widget.consultationId)
            .isNotEmpty
        ? assessments
            .firstWhere((a) => a.consultationId == widget.consultationId)
        : (assessments.isEmpty ? null : assessments.last);
    if (categories.isNotEmpty) {
      final resolved = repo.resolveProtocolProducts(
        organizationId: orgId,
        categories: categories,
        areaCm2: last?.areaCm2,
        volumeCm3: last?.volumeCm3,
        exudateLevel: assess?.exudateAmount.name,
        zoneGroup: ZoneGroup.forLocation(wound?.bodyLocationPrimary),
        infectionSuspected: assess?.infectionCriteria.isNotEmpty,
        siteId: siteId,
      );
      for (final r in resolved) {
        final tag = KuraTag.values.where((t) => t.dbValue == r.category);
        _supplies.add(_SupplyRow(
          method: tag.isEmpty ? r.category : tag.first.label,
          inventoryItemId: r.inventoryItemId,
          name: r.name,
          unitCost: r.unitCost,
          unitPrice: r.unitPrice,
          currency: r.currency,
        )..qty = r.quantity <= 0 ? 1 : r.quantity);
      }
      if (_supplies.isNotEmpty) return;
    }

    // 2) Fallback: mapeo antiguo por (método, genérico) → producto Shopify.
    final mapGroups = repo.supplyMappingGroups(orgId);
    final inventory =
        repo.listInventoryItems(organizationId: orgId, siteId: siteId);
    final byProduct = <String, InventoryItem>{
      for (final it in inventory)
        if (it.shopifyProductId != null) it.shopifyProductId!: it
    };
    final seen = <String>{};
    for (final comp in components) {
      final ms =
          mapGroups[SupplyProductMapping.keyFor(comp.method, comp.product)] ??
              const [];
      for (final m in ms) {
        final item = byProduct[m.shopifyProductId];
        if (item == null || !seen.add(item.id)) continue;
        _supplies.add(_SupplyRow(
          method: comp.method,
          product: comp.product,
          inventoryItemId: item.id,
          name: item.name,
          unitCost: item.unitCost,
          unitPrice: item.unitPrice,
          currency: item.currency,
        ));
      }
    }
  }

  // ---- Sesiones ----
  // Sesiones movidas a mano (arrastre en la rejilla semanal). null = usar las
  // generadas por la cadencia. Se resetea cuando cambia la cadencia.
  List<DateTime>? _editedSessions;

  /// Sesiones efectivas: las editadas a mano si existen, si no las generadas.
  List<DateTime> get _sessions => _editedSessions ?? _generatedSessions;

  /// Mueve la sesión [i] a un nuevo día/hora (arrastre) y refresca conflictos.
  void _moveSession(int i, DateTime newStart) {
    final base = List<DateTime>.from(_sessions);
    if (i < 0 || i >= base.length) return;
    base[i] = newStart;
    setState(() => _editedSessions = base);
    _refreshConflicts().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// ¿La sesión [i] se empalma? Contra las propias sesiones del plan (±60 min)
  /// o contra el calendario de Acuity del especialista.
  bool _sessionConflictAt(int i) {
    final all = _sessions;
    if (i < 0 || i >= all.length) return false;
    final s = all[i];
    const w = Duration(minutes: 60);
    for (var j = 0; j < all.length; j++) {
      if (j == i) continue;
      if (all[j].difference(s).abs() < w) return true;
    }
    return _conflicts(s);
  }

  List<DateTime> get _generatedSessions {
    final out = <DateTime>[];
    // Modo "cada N horas": desde la fecha/hora de inicio, sumando el intervalo.
    if (_hourlyMode) {
      final startDt = DateTime(_startDate.year, _startDate.month,
          _startDate.day, _time.hour, _time.minute);
      final n = _sessionCount.clamp(1, 60);
      final step = _intervalHours.clamp(1, 24 * 30);
      for (var k = 0; k < n; k++) {
        out.add(startDt.add(Duration(hours: step * k)));
      }
      return out;
    }
    // Modo "días de la semana" (comportamiento original).
    if (_weekdays.isEmpty) return out;
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
    for (var d = 0; d < _weeks * 7; d++) {
      final day = start.add(Duration(days: d));
      if (_weekdays.contains(day.weekday)) {
        out.add(DateTime(day.year, day.month, day.day, _time.hour, _time.minute));
      }
    }
    return out;
  }

  Future<void> _refreshConflicts() async {
    if (!_acuityMode) {
      _acuityAppts = const [];
      return;
    }
    final sessions = _sessions;
    if (sessions.isEmpty) {
      _acuityAppts = const [];
      return;
    }
    try {
      final svc = ref.read(acuityServiceProvider);
      _acuityAppts = await svc.appointmentsBetween(
        sessions.first.subtract(const Duration(days: 1)),
        sessions.last.add(const Duration(days: 1)),
      );
    } catch (_) {
      _acuityAppts = const [];
    }
  }

  /// Una sesión choca si cae dentro de ±60 min de una cita del especialista.
  bool _conflicts(DateTime s) {
    const window = Duration(minutes: 60);
    for (final a in _acuityAppts) {
      if (a.isCanceled || a.datetime == null) continue;
      if (_staffId != null && a.staffId != null && a.staffId != _staffId) {
        continue;
      }
      if (a.datetime!.difference(s).abs() < window) return true;
    }
    return false;
  }

  /// Fila etiqueta + contador -/valor/+ acotado a [min].. [max].
  Widget _counterRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required void Function(int) onChanged,
  }) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: KuraColors.darkText.withValues(alpha: 0.8))),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  Future<void> _onCadenceChanged() async {
    // Al cambiar la cadencia se regeneran las sesiones: descarta los movimientos
    // manuales previos (ya no aplican a la nueva grilla).
    _editedSessions = null;
    setState(() {});
    await _refreshConflicts();
    if (mounted) setState(() {});
  }

  // ---- Guardado ----
  Future<void> _save({required bool accept}) async {
    final repo = _repo;
    final orgId = _orgId;
    if (repo == null || orgId == null) return;
    if (_sessions.isEmpty) {
      _snack(_hourlyMode
          ? 'Define el intervalo y el número de sesiones.'
          : 'Define al menos un día de la semana para generar sesiones.');
      return;
    }
    setState(() => _saving = true);
    try {
      var program = repo.programForConsultation(widget.consultationId);
      program ??= await repo.createTreatmentProgram(
        organizationId: orgId,
        patientId: widget.patientId,
        woundId: widget.woundId,
        consultationId: widget.consultationId,
        siteId: _siteId,
        staffId: _staffId,
        weeks: _weeks,
        cadenceMode: _hourlyMode ? 'hourly' : 'weekly',
        intervalHours: _hourlyMode ? _intervalHours : null,
        sessionCount: _hourlyMode ? _sessionCount : null,
        createdBy: ref.read(sessionProvider).user?.id,
      );
      await repo.saveProgramSupplies(program.id, orgId, [
        for (final s in _supplies)
          (
            method: s.method,
            product: s.product,
            inventoryItemId: s.inventoryItemId,
            name: s.name,
            quantityPerSession: s.qty,
            isMonthly: s.perMonth,
            unitCost: s.unitCost,
            unitPrice: s.unitPrice,
            currency: s.currency,
          ),
      ]);
      await repo.saveProgramSessions(program.id, orgId, widget.patientId, [
        for (final s in _sessions)
          (
            staffId: _staffId,
            scheduledAt: s,
            endAt: s.add(const Duration(minutes: 60)),
            appointmentRef: null,
          ),
      ]);
      await repo.updateProgramStatus(
        program.id,
        accept ? ProgramStatus.aceptado : ProgramStatus.borrador,
        acceptedAt: accept ? DateTime.now() : null,
      );

      // Al ACEPTAR en un centro con Acuity: empuja las sesiones a Acuity
      // (fuente de verdad). Si no está configurado o falla, quedan internas.
      String extra = '';
      if (accept && _acuityMode) {
        extra = await _pushSessionsToAcuity(repo, orgId, program.id);
      }

      if (!mounted) return;
      _snack(accept
          ? 'Plan aceptado. Las sesiones quedaron registradas.$extra'
          : 'Borrador del plan guardado.');
      context.go('/patients/${widget.patientId}');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('$e'.replaceFirst('Exception: ', ''));
      }
    }
  }

  /// Empuja las sesiones (planeadas) del programa a Acuity con admin=true
  /// (fuerza el horario), en el calendario del Kurador y con el paciente como
  /// cliente. Guarda el ref `acuity:ID` y marca la sesión como agendada. Las
  /// que fallen quedan internas. Devuelve un texto-resumen para el snack.
  Future<String> _pushSessionsToAcuity(
      DataRepository repo, String orgId, String programId) async {
    // Tipo de cita: preferir el del SITIO del programa; fallback al del centro.
    final typeId = repo.siteById(_siteId)?.acuitySessionTypeId ??
        repo.organizationById(orgId)?.acuitySessionTypeId;
    if (typeId == null) {
      return ' (configura el tipo de cita del sitio en Admin para agendarlas en Acuity)';
    }
    final patient = repo.getPatient(widget.patientId);
    if (patient == null) return '';
    final parts = patient.fullName.trim().split(RegExp(r'\s+'));
    final firstName = parts.isEmpty ? 'Paciente' : parts.first;
    final lastName =
        parts.length > 1 ? parts.sublist(1).join(' ') : 'KuraTracker';
    final email = (patient.email?.trim().isNotEmpty ?? false)
        ? patient.email!.trim()
        : 'kura+${patient.id}@kuramas.com';
    final calendarId =
        _staffId == null ? null : repo.getStaff(_staffId!)?.acuityCalendarId;

    final svc = ref.read(acuityServiceProvider);
    final sessions = repo
        .listProgramSessions(programId)
        .where((s) => s.status == SessionStatus.planeada)
        .toList();
    var ok = 0, fail = 0;
    for (final s in sessions) {
      try {
        final appt = await svc.createAppointmentAdmin(
          appointmentTypeID: typeId,
          datetime: s.scheduledAt.toIso8601String(),
          firstName: firstName,
          lastName: lastName,
          email: email,
          calendarID: calendarId,
          phone: patient.mobilePhone,
        );
        final id = appt['id'];
        if (id == null) {
          fail++;
          continue;
        }
        await repo.updateProgramSessionAcuity(
          s.id,
          appointmentRef: 'acuity:$id',
          status: SessionStatus.agendada,
        );
        ok++;
      } catch (_) {
        fail++;
      }
    }
    if (ok == 0 && fail == 0) return '';
    if (fail == 0) return ' $ok cita(s) creada(s) en Acuity.';
    return ' $ok en Acuity, $fail quedaron internas (revisar).';
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _addManualProduct() async {
    final repo = _repo;
    final orgId = _orgId;
    if (repo == null || orgId == null) return;
    final items = repo.listInventoryItems(organizationId: orgId, siteId: _siteId);
    final existing = _supplies.map((s) => s.inventoryItemId).toSet();
    final pool = items.where((i) => !existing.contains(i.id)).toList();
    if (pool.isEmpty) {
      _snack('No hay más productos en el inventario del sitio.');
      return;
    }
    final picked = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPicker(items: pool, money: _money),
    );
    if (picked != null) {
      setState(() => _supplies.add(_SupplyRow(
            method: 'Material del centro',
            inventoryItemId: picked.id,
            name: picked.name,
            unitCost: picked.unitCost,
            unitPrice: picked.unitPrice,
            currency: picked.currency,
          )));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final sessions = _sessions;
    final conflicts = [
      for (var i = 0; i < sessions.length; i++)
        if (_sessionConflictAt(i)) i
    ].length;

    // Insumos agrupados por procedimiento.
    final byMethod = <String, List<_SupplyRow>>{};
    for (final s in _supplies) {
      byMethod.putIfAbsent(s.method, () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan de tratamiento del mes'),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => context.go('/patients/${widget.patientId}'),
            child: const Text('Omitir'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Text(
            'A partir de la valoración, define el plan del mes: insumos por '
            'procedimiento y la cadencia de las sesiones. Cada insumo puede ser '
            '"por sesión" (se multiplica por las sesiones) o "mensual" para '
            'productos multidosis (la cantidad ya es la del mes). Al aceptarlo, '
            'cada seguimiento vendrá pre-cargado.',
            style: TextStyle(
                fontSize: 12, color: KuraColors.darkText.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 16),

          // ---- Insumos por procedimiento ----
          _sectionTitle('Insumos por procedimiento', 'por sesión o mensual'),
          if (_supplies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No hay insumos del plan mapeados en el inventario. Agrégalos '
                'manualmente con el botón de abajo.',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.5)),
              ),
            )
          else
            for (final entry in byMethod.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(entry.key,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: KuraColors.primary)),
              ),
              for (final s in entry.value) _supplyTile(s),
            ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving ? null : _addManualProduct,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar producto'),
            ),
          ),
          const Divider(height: 28),

          // ---- Cadencia ----
          _sectionTitle('Cadencia de sesiones', null),
          const SizedBox(height: 8),
          // Selector de modo: días de la semana vs cada N horas (0088).
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Días de la semana'),
                icon: Icon(Icons.calendar_view_week, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text('Cada N horas'),
                icon: Icon(Icons.hourglass_bottom, size: 16),
              ),
            ],
            selected: {_hourlyMode},
            onSelectionChanged: (s) {
              setState(() => _hourlyMode = s.first);
              _onCadenceChanged();
            },
          ),
          const SizedBox(height: 12),
          if (_hourlyMode) ...[
            Text('Intervalo entre sesiones',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.7))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final h in _kIntervalPresets)
                  ChoiceChip(
                    label: Text('${h}h'),
                    selected: _intervalHours == h,
                    onSelected: (_) {
                      setState(() => _intervalHours = h);
                      _onCadenceChanged();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ] else ...[
            Text('Días de la semana',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.7))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (var wd = 1; wd <= 7; wd++)
                  FilterChip(
                    label: Text(_kWeekdayLabels[wd - 1]),
                    selected: _weekdays.contains(wd),
                    onSelected: (sel) {
                      setState(() {
                        if (sel) {
                          _weekdays.add(wd);
                        } else {
                          _weekdays.remove(wd);
                        }
                      });
                      _onCadenceChanged();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _pickerTile(
                  icon: Icons.schedule,
                  label: 'Hora',
                  value: _fmtTime(DateTime(2020, 1, 1, _time.hour, _time.minute)),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: _time);
                    if (t != null) {
                      setState(() => _time = t);
                      _onCadenceChanged();
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _pickerTile(
                  icon: Icons.event,
                  label: 'Inicio',
                  value: _fmtDay(_startDate),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 180)),
                    );
                    if (d != null) {
                      setState(() => _startDate = d);
                      _onCadenceChanged();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_hourlyMode)
            _counterRow(
              label: 'Número de sesiones',
              value: _sessionCount,
              min: 1,
              max: 60,
              onChanged: (v) {
                setState(() => _sessionCount = v);
                _onCadenceChanged();
              },
            )
          else
            _counterRow(
              label: 'Semanas',
              value: _weeks,
              min: 1,
              max: 8,
              onChanged: (v) {
                setState(() => _weeks = v);
                _onCadenceChanged();
              },
            ),
          const Divider(height: 28),

          // ---- Sesiones generadas ----
          _sectionTitle('Sesiones del mes', '${sessions.length}'),
          if (conflicts > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                '$conflicts sesión(es) se empalman (con otra sesión del plan o '
                'con el calendario de Acuity). Arrástralas en la rejilla a otro '
                'día/hora para reacomodarlas.',
                style: const TextStyle(fontSize: 12, color: KuraColors.danger),
              ),
            ),
          const SizedBox(height: 4),
          if (sessions.isEmpty)
            Text(
                _hourlyMode
                    ? 'Define el intervalo y el número de sesiones.'
                    : 'Selecciona al menos un día para generar sesiones.',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.5)))
          else
            WeekScheduler(
              sessions: sessions,
              isConflict: _sessionConflictAt,
              onMove: _moveSession,
            ),
          const Divider(height: 28),

          // ---- Explosión de materiales ----
          _sectionTitle('Explosión de materiales del mes',
              'para reservar stock'),
          const SizedBox(height: 6),
          if (_supplies.isEmpty)
            Text('Sin insumos.',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.5)))
          else
            for (final s in _supplies)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(s.name, style: const TextStyle(fontSize: 13))),
                    if (s.perMonth)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text('mensual',
                            style: TextStyle(
                                fontSize: 10,
                                color:
                                    KuraColors.darkText.withValues(alpha: 0.45))),
                      ),
                    Text(
                        '${_fmtQty(s.perMonth ? s.qty : s.qty * sessions.length)} u',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(accept: false),
                  child: const Text('Guardar borrador'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(accept: true),
                  child: Text(_saving ? 'Guardando…' : 'Aceptar e iniciar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String? trailing) => Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          if (trailing != null)
            Text(trailing,
                style: TextStyle(
                    fontSize: 12, color: KuraColors.darkText.withValues(alpha: 0.5))),
        ],
      );

  Widget _supplyTile(_SupplyRow s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: const TextStyle(fontSize: 13)),
                  if (s.unitAmount > 0)
                    Text(_money(s.unitAmount),
                        style: TextStyle(
                            fontSize: 11,
                            color: KuraColors.darkText.withValues(alpha: 0.5))),
                  const SizedBox(height: 4),
                  _modeChip(s),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: () => setState(() {
                if (s.qty > 1) {
                  s.qty -= 1;
                } else {
                  _supplies.remove(s);
                }
              }),
            ),
            Text(_fmtQty(s.qty),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: () => setState(() => s.qty += 1),
            ),
          ],
        ),
      );

  /// Toggle por insumo: "por sesión" (consumible de cada cura) vs "mensual"
  /// (multidosis, se compra 1–2 veces al mes). Cambia cómo se cuenta en la
  /// explosión de materiales del mes.
  Widget _modeChip(_SupplyRow s) {
    final monthly = s.perMonth;
    final color =
        monthly ? KuraColors.primary : KuraColors.darkText.withValues(alpha: 0.55);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => s.perMonth = !s.perMonth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(monthly ? Icons.calendar_month : Icons.repeat,
                size: 12, color: color),
            const SizedBox(width: 4),
            Text(monthly ? 'mensual (multidosis)' : 'por sesión',
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            Icon(Icons.swap_horiz, size: 12, color: color.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: KuraColors.borderSubtle),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: KuraColors.primary),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: KuraColors.darkText.withValues(alpha: 0.5))),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      );

  static String _fmtQty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Selector simple de producto del inventario, con buscador.
class _ProductPicker extends StatefulWidget {
  final List<InventoryItem> items;
  final String Function(double) money;
  const _ProductPicker({required this.items, required this.money});
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.items
        : widget.items
            .where((i) => i.name.toLowerCase().contains(q))
            .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Agregar producto',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar…',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Sin resultados.')),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final it = filtered[i];
                      return ListTile(
                        dense: true,
                        title: Text(it.name),
                        subtitle: Text(
                            widget.money(it.unitPrice ?? it.unitCost ?? 0)),
                        onTap: () => Navigator.of(context).pop(it),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
