import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/tokens.dart';
import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../core/widgets/kura_primary_fab.dart';
import '../../models/app_user.dart';
import '../../models/appointment.dart';
import '../../models/manual_appointment.dart';
import '../../models/patient.dart';
import '../../services/acuity_service.dart';
import '../../services/data_repository.dart';

/// Agenda de citas (Acuity Scheduling). El clínico ve SUS citas y el admin las
/// del centro (el aislamiento lo aplica la RLS de la tabla `appointments`).
/// Las altas/cambios pasan por la Edge Function `acuity-proxy`.
///
/// UI: encabezado resumen + dos vistas conmutables (Día / Semana). En móvil la
/// vista por defecto es Día (lista agrupada por jornada); en escritorio,
/// Semana (columnas por día). El admin ve una insignia con el Kurador dueño de
/// cada cita y puede filtrar por uno.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

enum _AgendaView { dia, semana }

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  // null = automático según el ancho (día en móvil, semana en escritorio).
  _AgendaView? _view;
  // Lunes de la semana visible en la vista Semana.
  DateTime _weekStart = _mondayOf(DateTime.now());
  // Día seleccionado dentro de la vista Semana en pantallas angostas.
  DateTime? _selectedDay;
  // Vista Día: si mostrar también las citas pasadas.
  bool _showHistory = false;
  // Admin: filtro por Kurador (staff_id) o null para todos.
  String? _kuradorFilter;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    final isAdmin = user?.role == AppRole.admin;
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;
    final mode = repo?.schedulingModeFor(user?.organizationId) ?? 'none';

    // Modo de agenda por centro (0020): manual (gestión local) / acuity
    // (integración) / none (sin configurar).
    if (mode == 'manual') {
      return _ManualAgenda(
        isAdmin: isAdmin,
        organizationId: user?.organizationId,
        currentStaffId: user?.staffId,
        currentUserId: user?.id,
      );
    }
    if (mode == 'none') {
      return _AgendaModeSetup(isAdmin: isAdmin, organizationId: user?.organizationId);
    }

    final service = ref.watch(acuityServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Agenda del centro' : 'Mi agenda'),
        actions: const [UserMenuButton()],
      ),
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
                // Citas válidas (no canceladas y con fecha). Se conservan
                // pasadas y futuras: las vistas deciden qué mostrar.
                final all = snapshot.data!
                    .where((a) => !a.isCanceled && a.datetime != null)
                    .toList()
                  ..sort((a, b) => a.datetime!.compareTo(b.datetime!));
                return _buildContent(context, all, isAdmin, service);
              },
            ),
      floatingActionButton: service.isAvailable
          ? KuraPrimaryFab(
              onPressed: () => _openScheduleSheet(context, service),
              icon: Icons.event_available,
              label: 'Nueva cita',
            )
          : null,
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Appointment> all,
    bool isAdmin,
    AcuityService service,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final view = _view ?? (isWide ? _AgendaView.semana : _AgendaView.dia);

    // Nombres de Kurador por staff_id (solo relevante para el admin).
    final staffNames = <String, String>{};
    if (isAdmin) {
      final repo = ref.watch(dataRepositoryProvider).valueOrNull;
      if (repo != null) {
        for (final s in repo.listStaff()) {
          staffNames[s.id] = s.fullName;
        }
      }
    }

    // Filtro por Kurador (admin).
    final filtered = _kuradorFilter == null
        ? all
        : all.where((a) => a.staffId == _kuradorFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryHeader(appointments: all),
        _Controls(
          view: view,
          onViewChanged: (v) => setState(() => _view = v),
          isAdmin: isAdmin,
          showHistory: _showHistory,
          onHistoryChanged: (v) => setState(() => _showHistory = v),
          weekStart: _weekStart,
          onWeekDelta: (days) => setState(() {
            _weekStart = _dayStart(_weekStart.add(Duration(days: days)));
            _selectedDay = null;
          }),
          onWeekToday: () => setState(() {
            _weekStart = _mondayOf(DateTime.now());
            _selectedDay = null;
          }),
          kuradorFilter: _kuradorFilter,
          kuradorOptions: _kuradorOptions(all, staffNames),
          onKuradorChanged: (v) => setState(() => _kuradorFilter = v),
        ),
        const Divider(height: 1),
        Expanded(
          child: view == _AgendaView.dia
              ? _DayAgenda(
                  appointments: filtered,
                  showHistory: _showHistory,
                  isAdmin: isAdmin,
                  staffNames: staffNames,
                  service: service,
                )
              : _WeekAgenda(
                  appointments: filtered,
                  weekStart: _weekStart,
                  isWide: isWide,
                  selectedDay: _selectedDay,
                  onSelectDay: (d) => setState(() => _selectedDay = d),
                  isAdmin: isAdmin,
                  staffNames: staffNames,
                  service: service,
                ),
        ),
      ],
    );
  }

  /// Opciones de filtro por Kurador: (staffId, nombre) de los que tengan al
  /// menos una cita. Vacío si hay 0/1 Kurador (no vale la pena el filtro).
  List<MapEntry<String, String>> _kuradorOptions(
      List<Appointment> all, Map<String, String> staffNames) {
    final ids = all.map((a) => a.staffId).whereType<String>().toSet();
    if (ids.length < 2) return const [];
    final entries = ids
        .map((id) => MapEntry(id, staffNames[id] ?? 'Kurador'))
        .toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return entries;
  }
}

// ---------------------------------------------------------------------------
// Encabezado resumen
// ---------------------------------------------------------------------------

class _SummaryHeader extends StatelessWidget {
  final List<Appointment> appointments;
  const _SummaryHeader({required this.appointments});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = _dayStart(now);
    final weekStart = _mondayOf(now);
    final weekEnd = weekStart.add(const Duration(days: 7));

    final todayCount = appointments.where((a) => _sameDay(a.datetime!, now)).length;
    final weekCount = appointments
        .where((a) => !a.datetime!.isBefore(weekStart) && a.datetime!.isBefore(weekEnd))
        .length;
    Appointment? next;
    for (final a in appointments) {
      if (a.datetime!.isAfter(now)) {
        next = a;
        break; // 'appointments' viene ordenada ascendente
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KuraPalette.heroTop, KuraPalette.heroBottom],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: KuraPalette.brandPrimary.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hoy · ${_dayLong(today)}',
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  todayCount == 0
                      ? 'Sin citas hoy'
                      : '$todayCount ${todayCount == 1 ? 'cita' : 'citas'}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (next != null) ...[
                Text('Próxima',
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                Text(
                  '${_dayLabel(next.datetime!)} · ${DateFormat('HH:mm').format(next.datetime!)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Esta semana: $weekCount',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controles (toggle vista + navegación semana + historial + filtro Kurador)
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  final _AgendaView view;
  final ValueChanged<_AgendaView> onViewChanged;
  final bool isAdmin;
  final bool showHistory;
  final ValueChanged<bool> onHistoryChanged;
  final DateTime weekStart;
  final ValueChanged<int> onWeekDelta;
  final VoidCallback onWeekToday;
  final String? kuradorFilter;
  final List<MapEntry<String, String>> kuradorOptions;
  final ValueChanged<String?> onKuradorChanged;

  const _Controls({
    required this.view,
    required this.onViewChanged,
    required this.isAdmin,
    required this.showHistory,
    required this.onHistoryChanged,
    required this.weekStart,
    required this.onWeekDelta,
    required this.onWeekToday,
    required this.kuradorFilter,
    required this.kuradorOptions,
    required this.onKuradorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Toggle de vista.
              ChoiceChip(
                label: const Text('Día'),
                selected: view == _AgendaView.dia,
                selectedColor: KuraColors.primary.withOpacity(0.15),
                onSelected: (_) => onViewChanged(_AgendaView.dia),
              ),
              ChoiceChip(
                label: const Text('Semana'),
                selected: view == _AgendaView.semana,
                selectedColor: KuraColors.primary.withOpacity(0.15),
                onSelected: (_) => onViewChanged(_AgendaView.semana),
              ),
              if (view == _AgendaView.dia)
                FilterChip(
                  label: const Text('Historial'),
                  avatar: const Icon(Icons.history, size: 16),
                  selected: showHistory,
                  selectedColor: KuraColors.primary.withOpacity(0.15),
                  onSelected: onHistoryChanged,
                ),
              if (kuradorOptions.isNotEmpty) _kuradorDropdown(),
            ],
          ),
          if (view == _AgendaView.semana) ...[
            const SizedBox(height: 8),
            _weekNav(),
          ],
        ],
      ),
    );
  }

  Widget _kuradorDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: KuraColors.primary.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: kuradorFilter,
          isDense: true,
          icon: const Icon(Icons.filter_list, size: 18),
          hint: const Text('Kurador', style: TextStyle(fontSize: 13)),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Todos los Kuradores')),
            ...kuradorOptions.map(
              (e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
            ),
          ],
          onChanged: onKuradorChanged,
        ),
      ),
    );
  }

  Widget _weekNav() {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final sameMonth = weekStart.month == weekEnd.month;
    final label = sameMonth
        ? '${weekStart.day}–${weekEnd.day} ${_mo[weekStart.month - 1]}'
        : '${weekStart.day} ${_mo[weekStart.month - 1]} – ${weekEnd.day} ${_mo[weekEnd.month - 1]}';
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Semana anterior',
          onPressed: () => onWeekDelta(-7),
        ),
        Expanded(
          child: Center(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
        TextButton(onPressed: onWeekToday, child: const Text('Hoy')),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Semana siguiente',
          onPressed: () => onWeekDelta(7),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Vista Día: lista agrupada por jornada
// ---------------------------------------------------------------------------

class _DayAgenda extends StatelessWidget {
  final List<Appointment> appointments;
  final bool showHistory;
  final bool isAdmin;
  final Map<String, String> staffNames;
  final AcuityService service;

  const _DayAgenda({
    required this.appointments,
    required this.showHistory,
    required this.isAdmin,
    required this.staffNames,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final today = _dayStart(DateTime.now());
    final visible = showHistory
        ? appointments
        : appointments.where((a) => !_dayStart(a.datetime!).isBefore(today)).toList();
    if (visible.isEmpty) {
      return _AgendaEmpty(
        message: showHistory ? 'Sin citas registradas.' : 'Sin citas próximas',
      );
    }

    // Agrupar por día conservando el orden (asc). En modo historial se
    // muestra de más reciente a más antiguo para que lo último quede arriba.
    final ordered = showHistory ? visible.reversed.toList() : visible;
    final groups = <DateTime, List<Appointment>>{};
    for (final a in ordered) {
      groups.putIfAbsent(_dayStart(a.datetime!), () => []).add(a);
    }

    final children = <Widget>[];
    groups.forEach((day, appts) {
      children.add(_DayHeader(day: day, count: appts.length));
      for (final a in appts) {
        children.add(_AppointmentTile(
          appointment: a,
          service: service,
          kuradorName: isAdmin ? staffNames[a.staffId] : null,
        ));
      }
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: children,
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final int count;
  const _DayHeader({required this.day, required this.count});

  @override
  Widget build(BuildContext context) {
    final isToday = _sameDay(day, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Text(
            _dayLabel(day),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: isToday ? KuraColors.primary : KuraColors.darkText,
            ),
          ),
          const SizedBox(width: 8),
          Text('· $count', style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.5))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vista Semana: ancha = 7 columnas; angosta = tira de días + lista del día
// ---------------------------------------------------------------------------

class _WeekAgenda extends StatelessWidget {
  final List<Appointment> appointments;
  final DateTime weekStart;
  final bool isWide;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onSelectDay;
  final bool isAdmin;
  final Map<String, String> staffNames;
  final AcuityService service;

  const _WeekAgenda({
    required this.appointments,
    required this.weekStart,
    required this.isWide,
    required this.selectedDay,
    required this.onSelectDay,
    required this.isAdmin,
    required this.staffNames,
    required this.service,
  });

  List<Appointment> _forDay(DateTime day) =>
      appointments.where((a) => _sameDay(a.datetime!, day)).toList();

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => _dayStart(weekStart.add(Duration(days: i))));
    return isWide ? _wide(days) : _narrow(context, days);
  }

  Widget _wide(List<DateTime> days) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      child: Row(
        // stretch: cada columna recibe la altura completa (tight) para que el
        // Expanded(ListView) interno tenga altura acotada y las 7 columnas
        // queden a la misma altura (cuadrícula de semana).
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final day in days)
            Expanded(
              child: _WeekColumn(
                day: day,
                appts: _forDay(day),
                isAdmin: isAdmin,
                staffNames: staffNames,
                service: service,
              ),
            ),
        ],
      ),
    );
  }

  Widget _narrow(BuildContext context, List<DateTime> days) {
    // Día seleccionado: el provisto si cae en la semana; si no, hoy (si está
    // en la semana) o el primer día.
    DateTime selected = selectedDay ?? DateTime.now();
    if (!days.any((d) => _sameDay(d, selected))) {
      final today = DateTime.now();
      selected = days.any((d) => _sameDay(d, today)) ? _dayStart(today) : days.first;
    }
    final dayAppts = _forDay(selected)..sort((a, b) => a.datetime!.compareTo(b.datetime!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final day in days)
                Expanded(
                  child: _WeekStripCell(
                    day: day,
                    count: _forDay(day).length,
                    selected: _sameDay(day, selected),
                    onTap: () => onSelectDay(_dayStart(day)),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: dayAppts.isEmpty
              ? _AgendaEmpty(message: 'Sin citas el ${_dayLabel(selected)}')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    for (final a in dayAppts)
                      _AppointmentTile(
                        appointment: a,
                        service: service,
                        kuradorName: isAdmin ? staffNames[a.staffId] : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _WeekStripCell extends StatelessWidget {
  final DateTime day;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _WeekStripCell({
    required this.day,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = _sameDay(day, DateTime.now());
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? KuraColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isToday && !selected
              ? Border.all(color: KuraColors.primary.withOpacity(0.5))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _wd[day.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white70 : KuraColors.darkText.withOpacity(0.6),
              ),
            ),
            Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : KuraColors.darkText,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: count == 0
                    ? Colors.transparent
                    : (selected ? Colors.white24 : KuraColors.primary.withOpacity(0.15)),
                shape: BoxShape.circle,
              ),
              child: count == 0
                  ? null
                  : Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : KuraColors.primary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Columna de un día en la vista Semana ancha (escritorio).
class _WeekColumn extends StatelessWidget {
  final DateTime day;
  final List<Appointment> appts;
  final bool isAdmin;
  final Map<String, String> staffNames;
  final AcuityService service;

  const _WeekColumn({
    required this.day,
    required this.appts,
    required this.isAdmin,
    required this.staffNames,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = _sameDay(day, DateTime.now());
    final sorted = [...appts]..sort((a, b) => a.datetime!.compareTo(b.datetime!));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isToday ? KuraColors.primary.withOpacity(0.05) : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KuraColors.darkText.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Column(
              children: [
                Text(
                  _wd[day.weekday - 1],
                  style: TextStyle(
                    fontSize: 11,
                    color: KuraColors.darkText.withOpacity(0.6),
                  ),
                ),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isToday ? KuraColors.primary : KuraColors.darkText,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: sorted.isEmpty
                ? Center(
                    child: Text('—',
                        style: TextStyle(color: KuraColors.darkText.withOpacity(0.25))),
                  )
                : ListView(
                    padding: const EdgeInsets.all(6),
                    children: [
                      for (final a in sorted)
                        _WeekChip(
                          appointment: a,
                          service: service,
                          kuradorName: isAdmin ? staffNames[a.staffId] : null,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Cita compacta dentro de una columna de la vista Semana ancha.
class _WeekChip extends StatelessWidget {
  final Appointment appointment;
  final AcuityService service;
  final String? kuradorName;
  const _WeekChip({required this.appointment, required this.service, this.kuradorName});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showAppointmentActions(context, service, appointment),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: KuraColors.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: KuraColors.primary, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('HH:mm').format(appointment.datetime!),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            Text(
              appointment.patientName.isEmpty ? 'Cita' : appointment.patientName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            if (kuradorName != null)
              Text(kuradorName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: KuraColors.darkText.withOpacity(0.55))),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de cita (vistas Día y Semana angosta)
// ---------------------------------------------------------------------------

class _AppointmentTile extends StatelessWidget {
  final Appointment appointment;
  final AcuityService service;
  final String? kuradorName;
  const _AppointmentTile({
    required this.appointment,
    required this.service,
    this.kuradorName,
  });

  @override
  Widget build(BuildContext context) {
    final dt = appointment.datetime!;
    final isPast = dt.isBefore(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showAppointmentDetail(context, service, appointment),
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Bloque de hora prominente.
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: KuraColors.primary.withOpacity(isPast ? 0.06 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('HH:mm').format(dt),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isPast ? KuraColors.darkText.withOpacity(0.5) : KuraColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.patientName.isEmpty ? 'Cita' : appointment.patientName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (appointment.appointmentType != null)
                        _MiniChip(
                          icon: Icons.medical_services_outlined,
                          label: appointment.appointmentType!,
                        ),
                      if (kuradorName != null)
                        _MiniChip(icon: Icons.person_outline, label: kuradorName!),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'detail') {
                  _showAppointmentDetail(context, service, appointment);
                } else if (v == 'cancel') {
                  await _confirmCancel(context, service, appointment);
                } else if (v == 'reschedule') {
                  await _openScheduleSheet(context, service, rescheduleId: appointment.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'detail', child: Text('Ver detalle')),
                PopupMenuItem(value: 'reschedule', child: Text('Reagendar')),
                PopupMenuItem(value: 'cancel', child: Text('Cancelar cita')),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: KuraColors.chipBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: KuraColors.darkText.withOpacity(0.6)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.75))),
        ],
      ),
    );
  }
}

/// Acciones (reagendar/cancelar) para una cita, mostradas al tocar un chip de
/// la vista Semana ancha (que no tiene menú propio por espacio).
void _showAppointmentActions(
    BuildContext context, AcuityService service, Appointment a) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(a.patientName.isEmpty ? 'Cita' : a.patientName,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(a.datetime == null
                ? '—'
                : DateFormat('dd/MM/yyyy · HH:mm').format(a.datetime!)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Ver detalle'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _showAppointmentDetail(context, service, a);
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Reagendar'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _openScheduleSheet(context, service, rescheduleId: a.id);
            },
          ),
          ListTile(
            leading: const Icon(Icons.cancel_outlined, color: KuraColors.danger),
            title: const Text('Cancelar cita'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _confirmCancel(context, service, a);
            },
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Detalle de cita: TODOS los campos de Acuity (columna appointments.raw)
// ---------------------------------------------------------------------------

void _showAppointmentDetail(BuildContext context, AcuityService service, Appointment a) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AppointmentDetailSheet(appointment: a, service: service),
  );
}

class _AppointmentDetailSheet extends StatelessWidget {
  final Appointment appointment;
  final AcuityService service;
  const _AppointmentDetailSheet({required this.appointment, required this.service});

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final raw = a.raw;
    // Lector tolerante: preferir raw (objeto completo de Acuity) y caer al
    // modelo si falta.
    String? r(String key) {
      final v = raw?[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final dt = a.datetime;
    final facts = <MapEntry<String, String>>[
      MapEntry('Paciente', a.patientName.isEmpty ? '—' : a.patientName),
      if ((r('phone') ?? a.phone) != null) MapEntry('Teléfono', r('phone') ?? a.phone!),
      if ((r('email') ?? a.email) != null) MapEntry('Email', r('email') ?? a.email!),
      if (dt != null) MapEntry('Fecha y hora', DateFormat('dd/MM/yyyy · HH:mm').format(dt)),
      if (r('duration') != null) MapEntry('Duración', '${r('duration')} min'),
      if ((a.appointmentType ?? r('type')) != null)
        MapEntry('Tipo', a.appointmentType ?? r('type')!),
      if (r('calendar') != null) MapEntry('Calendario (Kurador)', r('calendar')!),
      if (r('location') != null) MapEntry('Ubicación', r('location')!),
      MapEntry('Estado', a.status),
      if (r('price') != null) MapEntry('Precio', r('price')!),
      if (r('paid') != null) MapEntry('Pagado', _yesNo(raw?['paid'])),
      if (r('amountPaid') != null) MapEntry('Monto pagado', r('amountPaid')!),
      if (r('notes') != null) MapEntry('Notas', r('notes')!),
    ];

    final forms = (raw?['forms'] as List?) ?? const [];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                a.patientName.isEmpty ? 'Detalle de la cita' : a.patientName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              if (a.hasIntakePhoto) ...[
                const SizedBox(height: 12),
                _IntakePhotoView(service: service, path: a.intakePhotoPath!),
              ],
              const SizedBox(height: 12),
              _DetailSection(title: 'Datos de la cita', rows: facts),
              if (forms.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._formSections(forms),
              ],
              const SizedBox(height: 8),
              // Garantía de "todos los campos": el objeto crudo íntegro.
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Todos los campos (crudo)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                children: [
                  if (raw == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Esta cita no tiene datos crudos guardados '
                        '(sincronizada antes de habilitar el guardado completo).',
                        style: TextStyle(color: KuraColors.darkText.withOpacity(0.6)),
                      ),
                    )
                  else
                    _RawJsonBox(raw: raw),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _formSections(List<dynamic> forms) {
    final sections = <Widget>[];
    for (final f in forms) {
      if (f is! Map) continue;
      final name = (f['name'] ?? 'Formulario').toString();
      final values = (f['values'] as List?) ?? const [];
      final rows = <MapEntry<String, String>>[];
      for (final v in values) {
        if (v is! Map) continue;
        final label = (v['name'] ?? '').toString();
        final value = (v['value'] ?? '').toString().trim();
        if (label.isEmpty) continue;
        rows.add(MapEntry(label, value.isEmpty ? '—' : value));
      }
      if (rows.isNotEmpty) sections.add(_DetailSection(title: name, rows: rows));
    }
    return sections;
  }

  static String _yesNo(dynamic v) => v == true ? 'Sí' : 'No';
}

/// Foto de la herida del formulario de admisión (bucket privado acuity-intake).
/// Resuelve una signed URL de 1 h y la muestra; toca para verla en grande.
class _IntakePhotoView extends StatelessWidget {
  final AcuityService service;
  final String path;
  const _IntakePhotoView({required this.service, required this.path});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 4),
          child: Text('Foto de la herida',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        FutureBuilder<String?>(
          future: service.intakePhotoUrl(path),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final url = snap.data;
            if (url == null) {
              return Text('No se pudo cargar la foto.',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)));
            }
            return GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (dialogCtx) => Dialog(
                  child: InteractiveViewer(
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 160,
                    color: KuraColors.chipBg,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<MapEntry<String, String>> rows;
  const _DetailSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        ...rows.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(e.key,
                      style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6))),
                ),
                Expanded(child: SelectableText(e.value, style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RawJsonBox extends StatelessWidget {
  final Map<String, dynamic> raw;
  const _RawJsonBox({required this.raw});

  @override
  Widget build(BuildContext context) {
    String pretty;
    try {
      pretty = const JsonEncoder.withIndent('  ').convert(raw);
    } catch (_) {
      pretty = raw.toString();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KuraColors.chipBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copiar'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pretty));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copiado')),
                );
              },
            ),
          ),
          SelectableText(
            pretty,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Flujo de alta / reagenda (bottom sheet) — sin cambios de lógica
// ---------------------------------------------------------------------------

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
  final String message;
  const _AgendaEmpty({this.message = 'Sin citas próximas'});
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
            Text(message, style: TextStyle(color: KuraColors.darkText.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// AGENDA MANUAL (centros con scheduling_mode = 'manual') — CRUD local
// ===========================================================================

class _ManualAgenda extends ConsumerStatefulWidget {
  final bool isAdmin;
  final String? organizationId;
  final String? currentStaffId;
  final String? currentUserId;
  const _ManualAgenda({
    required this.isAdmin,
    required this.organizationId,
    required this.currentStaffId,
    required this.currentUserId,
  });

  @override
  ConsumerState<_ManualAgenda> createState() => _ManualAgendaState();
}

class _ManualAgendaState extends ConsumerState<_ManualAgenda> {
  bool _showHistory = false;
  String? _kuradorFilter;

  Future<void> _openForm(DataRepository repo, {ManualAppointment? existing}) async {
    final orgId = widget.organizationId;
    if (orgId == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ManualForm(
          repo: repo,
          isAdmin: widget.isAdmin,
          organizationId: orgId,
          currentStaffId: widget.currentStaffId,
          currentUserId: widget.currentUserId,
          existing: existing,
        ),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _cancel(DataRepository repo, ManualAppointment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Cancelar cita'),
        content: const Text('¿Cancelar esta cita?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: KuraColors.danger),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Cancelar cita'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.cancelManualAppointment(a.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;
    if (repo == null) {
      return Scaffold(appBar: _bar(), body: const Center(child: CircularProgressIndicator()));
    }

    final all = repo
        .listManualAppointments(
          organizationId: widget.isAdmin ? widget.organizationId : null,
          staffId: widget.isAdmin ? null : widget.currentStaffId,
        )
        .where((a) => !a.isCanceled)
        .toList()
      ..sort((a, b) => a.datetime.compareTo(b.datetime));

    final staffNames = {
      for (final s in repo.listStaff(organizationId: widget.organizationId)) s.id: s.fullName
    };
    String patientName(String? id) =>
        id == null ? 'Sin paciente' : (repo.getPatient(id)?.fullName ?? 'Paciente');

    final filtered =
        _kuradorFilter == null ? all : all.where((a) => a.staffId == _kuradorFilter).toList();

    final ids = all.map((a) => a.staffId).whereType<String>().toSet();
    final kuradorOptions = ids.length < 2
        ? <MapEntry<String, String>>[]
        : (ids.map((id) => MapEntry(id, staffNames[id] ?? 'Kurador')).toList()
          ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase())));

    final today = _dayStart(DateTime.now());
    final visible = _showHistory
        ? filtered
        : filtered.where((a) => !_dayStart(a.datetime).isBefore(today)).toList();
    final ordered = _showHistory ? visible.reversed.toList() : visible;

    return Scaffold(
      appBar: _bar(),
      floatingActionButton: widget.organizationId == null
          ? null
          : KuraPrimaryFab(
              onPressed: () => _openForm(repo),
              icon: Icons.event_available,
              label: 'Nueva cita',
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ManualSummary(appointments: all),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Historial'),
                  avatar: const Icon(Icons.history, size: 16),
                  selected: _showHistory,
                  selectedColor: KuraColors.primary.withOpacity(0.15),
                  onSelected: (v) => setState(() => _showHistory = v),
                ),
                if (kuradorOptions.isNotEmpty) _kuradorDropdown(kuradorOptions),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ordered.isEmpty
                ? _AgendaEmpty(
                    message: _showHistory ? 'Sin citas registradas.' : 'Sin citas próximas')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: _grouped(repo, ordered, staffNames, patientName),
                  ),
          ),
        ],
      ),
    );
  }

  AppBar _bar() => AppBar(
        title: Text(widget.isAdmin ? 'Agenda del centro' : 'Mi agenda'),
        actions: const [UserMenuButton()],
      );

  Widget _kuradorDropdown(List<MapEntry<String, String>> opts) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: KuraColors.primary.withOpacity(0.35)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _kuradorFilter,
            isDense: true,
            icon: const Icon(Icons.filter_list, size: 18),
            hint: const Text('Kurador', style: TextStyle(fontSize: 13)),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos los Kuradores')),
              ...opts.map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
            ],
            onChanged: (v) => setState(() => _kuradorFilter = v),
          ),
        ),
      );

  List<Widget> _grouped(
    DataRepository repo,
    List<ManualAppointment> items,
    Map<String, String> staffNames,
    String Function(String?) patientName,
  ) {
    final groups = <DateTime, List<ManualAppointment>>{};
    for (final a in items) {
      groups.putIfAbsent(_dayStart(a.datetime), () => []).add(a);
    }
    final out = <Widget>[];
    groups.forEach((day, appts) {
      out.add(_DayHeader(day: day, count: appts.length));
      for (final a in appts) {
        out.add(_ManualTile(
          appointment: a,
          patientName: patientName(a.patientId),
          kuradorName: widget.isAdmin ? staffNames[a.staffId] : null,
          onEdit: () => _openForm(repo, existing: a),
          onCancel: () => _cancel(repo, a),
        ));
      }
    });
    return out;
  }
}

/// Encabezado resumen de la agenda manual (mismo estilo que el de Acuity).
class _ManualSummary extends StatelessWidget {
  final List<ManualAppointment> appointments;
  const _ManualSummary({required this.appointments});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = _mondayOf(now);
    final weekEnd = weekStart.add(const Duration(days: 7));
    final todayCount = appointments.where((a) => _sameDay(a.datetime, now)).length;
    final weekCount = appointments
        .where((a) => !a.datetime.isBefore(weekStart) && a.datetime.isBefore(weekEnd))
        .length;
    ManualAppointment? next;
    for (final a in appointments) {
      if (a.datetime.isAfter(now)) {
        next = a;
        break;
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KuraPalette.heroTop, KuraPalette.heroBottom],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hoy · ${_dayLong(_dayStart(now))}',
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  todayCount == 0 ? 'Sin citas hoy' : '$todayCount ${todayCount == 1 ? 'cita' : 'citas'}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (next != null) ...[
                Text('Próxima',
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                Text('${_dayLabel(next.datetime)} · ${DateFormat('HH:mm').format(next.datetime)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Esta semana: $weekCount',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManualTile extends StatelessWidget {
  final ManualAppointment appointment;
  final String patientName;
  final String? kuradorName;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  const _ManualTile({
    required this.appointment,
    required this.patientName,
    required this.kuradorName,
    required this.onEdit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final dt = appointment.datetime;
    final isPast = dt.isBefore(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: KuraColors.primary.withOpacity(isPast ? 0.06 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat('HH:mm').format(dt),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isPast ? KuraColors.darkText.withOpacity(0.5) : KuraColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patientName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if ((appointment.title ?? '').isNotEmpty)
                          _MiniChip(
                              icon: Icons.medical_services_outlined, label: appointment.title!),
                        if (kuradorName != null)
                          _MiniChip(icon: Icons.person_outline, label: kuradorName!),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'cancel') onCancel();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'cancel', child: Text('Cancelar cita')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formulario de alta/edición de cita manual.
class _ManualForm extends StatefulWidget {
  final DataRepository repo;
  final bool isAdmin;
  final String organizationId;
  final String? currentStaffId;
  final String? currentUserId;
  final ManualAppointment? existing;
  const _ManualForm({
    required this.repo,
    required this.isAdmin,
    required this.organizationId,
    required this.currentStaffId,
    required this.currentUserId,
    required this.existing,
  });

  @override
  State<_ManualForm> createState() => _ManualFormState();
}

class _ManualFormState extends State<_ManualForm> {
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _notesCtrl =
      TextEditingController(text: widget.existing?.notes ?? '');
  String? _patientId;
  String? _staffId;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _patientId = e?.patientId;
    _staffId = e?.staffId ?? (widget.isAdmin ? null : widget.currentStaffId);
    final dt = e?.datetime ?? _nextHalfHour();
    _date = DateTime(dt.year, dt.month, dt.day);
    _time = TimeOfDay(hour: dt.hour, minute: dt.minute);
  }

  static DateTime _nextHalfHour() {
    final now = DateTime.now().add(const Duration(minutes: 30));
    return DateTime(now.year, now.month, now.day, now.hour, now.minute < 30 ? 30 : 0)
        .add(now.minute < 30 ? Duration.zero : const Duration(hours: 1));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final dt =
          DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
      final title = _titleCtrl.text.trim();
      final notes = _notesCtrl.text.trim();
      if (widget.existing == null) {
        await widget.repo.createManualAppointment(
          organizationId: widget.organizationId,
          datetime: dt,
          staffId: _staffId,
          patientId: _patientId,
          title: title.isEmpty ? null : title,
          notes: notes.isEmpty ? null : notes,
          createdByProfileId: widget.currentUserId,
        );
      } else {
        await widget.repo.updateManualAppointment(
          widget.existing!.id,
          staffId: _staffId,
          clearStaff: _staffId == null,
          patientId: _patientId,
          clearPatient: _patientId == null,
          title: title,
          datetime: dt,
          notes: notes,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = 'No se pudo guardar: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pacientes seleccionables: el admin ve los del centro; el clínico los suyos.
    final patients = widget.isAdmin
        ? widget.repo.listAllPatients()
        : (widget.currentStaffId != null
            ? widget.repo.listPatientsForStaff(widget.currentStaffId!)
            : <Patient>[]);
    final staff = widget.repo.listStaff(organizationId: widget.organizationId);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.existing == null ? 'Nueva cita' : 'Editar cita',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                value: _patientId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Paciente'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Sin paciente')),
                  ...patients.map((p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.fullName, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _patientId = v),
              ),
              const SizedBox(height: 12),
              if (widget.isAdmin) ...[
                DropdownButtonFormField<String?>(
                  value: _staffId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kurador'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sin asignar')),
                    ...staff.map((s) => DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text(s.fullName, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setState(() => _staffId = v),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('dd/MM/yyyy').format(_date)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => _date = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(_time.format(context)),
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: _time);
                        if (t != null) setState(() => _time = t);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tipo / motivo',
                  hintText: 'Curación, valoración, seguimiento…',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notas (opcional)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: KuraColors.danger)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.existing == null ? 'Crear cita' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla cuando el centro no tiene modo de agenda configurado. El admin puede
/// activar la agenda manual; el clínico ve un aviso.
class _AgendaModeSetup extends ConsumerWidget {
  final bool isAdmin;
  final String? organizationId;
  const _AgendaModeSetup({required this.isAdmin, required this.organizationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(acuityServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: const [UserMenuButton()],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_outlined,
                  size: 48, color: KuraColors.darkText.withOpacity(0.25)),
              const SizedBox(height: 12),
              const Text('Agenda no configurada',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                isAdmin
                    ? 'Elige cómo gestionar la agenda de este centro.'
                    : 'El administrador de tu centro aún no ha configurado la agenda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: KuraColors.darkText.withOpacity(0.6)),
              ),
              if (isAdmin && organizationId != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Usar agenda manual'),
                  onPressed: () async {
                    final repo = ref.read(dataRepositoryProvider).valueOrNull;
                    if (repo == null) return;
                    await repo.setSchedulingMode(organizationId!, 'manual');
                    ref.invalidate(dataRepositoryProvider);
                  },
                ),
                if (service.isAvailable) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.link),
                    label: const Text('Conectar Acuity'),
                    onPressed: () async {
                      final ok = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => Padding(
                          padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).viewInsets.bottom),
                          child: _AcuityConfigSheet(organizationId: organizationId!),
                        ),
                      );
                      if (ok == true) ref.invalidate(dataRepositoryProvider);
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Configuración de Acuity por centro (Fase 2b): el admin ingresa User ID + API
/// Key; se guarda por RPC, se prueba la conexión, se registran los webhooks
/// (?org=), se mapean calendarios y se activa scheduling_mode = 'acuity'.
class _AcuityConfigSheet extends ConsumerStatefulWidget {
  final String organizationId;
  const _AcuityConfigSheet({required this.organizationId});

  @override
  ConsumerState<_AcuityConfigSheet> createState() => _AcuityConfigSheetState();
}

class _AcuityConfigSheetState extends ConsumerState<_AcuityConfigSheet> {
  final _userIdCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  bool _loadingStatus = true;
  AcuityConfigStatus? _status;
  bool _busy = false;
  String? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    if (repo != null) {
      try {
        _status = await repo.getOrgAcuityStatus(widget.organizationId);
        if (_status != null) _userIdCtrl.text = _status!.userId;
      } catch (_) {}
    }
    if (mounted) setState(() => _loadingStatus = false);
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndConnect() async {
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    final service = ref.read(acuityServiceProvider);
    if (repo == null) return;
    final userId = _userIdCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    if (userId.isEmpty || apiKey.isEmpty) {
      setState(() => _error = 'User ID y API Key son obligatorios.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Guardando credenciales…';
    });
    try {
      await repo.setOrgAcuityCredentials(widget.organizationId, userId, apiKey);
      setState(() => _progress = 'Probando conexión con Acuity…');
      final err = await service.testConnection();
      if (err != null) {
        setState(() {
          _error = 'No se pudo conectar con Acuity. Revisa el User ID / API Key.\n$err';
          _busy = false;
          _progress = null;
        });
        return;
      }
      setState(() => _progress = 'Registrando webhooks…');
      await service.registerWebhooks(widget.organizationId);
      await repo.markAcuityWebhooks(widget.organizationId, true);
      setState(() => _progress = 'Mapeando calendarios…');
      try {
        await service.syncCalendars(widget.organizationId);
      } catch (_) {
        // el mapeo puede completarse luego; no bloquea la activación
      }
      setState(() => _progress = 'Activando agenda Acuity…');
      await repo.setSchedulingMode(widget.organizationId, 'acuity');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Conectar Acuity Scheduling',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Ingresa el User ID y la API Key de la cuenta de Acuity de este '
                'centro (Acuity → Integrations → API). La key se guarda de forma '
                'segura en el servidor y nunca se muestra completa.',
                style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
              ),
              const SizedBox(height: 12),
              if (_loadingStatus)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else if (_status != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KuraColors.chipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Ya conectado · User ID ${_status!.userId} · key ••••${_status!.keyLast4}'
                    ' · webhooks ${_status!.webhooksRegistered ? '✓' : '✗'}\n'
                    'Vuelve a ingresar la API Key para reconfigurar.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              TextField(
                controller: _userIdCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'User ID'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyCtrl,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
              if (_progress != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_progress!, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: KuraColors.danger, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
                onPressed: _busy ? null : _saveAndConnect,
                child: Text(_busy ? 'Conectando…' : 'Guardar y conectar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers de fecha (etiquetas en español sin depender de intl locale data)
// ---------------------------------------------------------------------------

const List<String> _wd = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const List<String> _mo = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
];

DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOf(DateTime d) {
  final s = _dayStart(d);
  return s.subtract(Duration(days: s.weekday - 1));
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Hoy" / "Mañana" / "Ayer" o "vie 25 jul".
String _dayLabel(DateTime d) {
  final diff = _dayStart(d).difference(_dayStart(DateTime.now())).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  if (diff == -1) return 'Ayer';
  return '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';
}

/// "25 jul" (para el encabezado resumen).
String _dayLong(DateTime d) => '${d.day} ${_mo[d.month - 1]}';
