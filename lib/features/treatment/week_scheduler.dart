import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';

/// Vista reducida de la semana para el plan de consultas: rejilla de 7 días ×
/// horas donde cada sesión se ubica por día/hora. Las sesiones que se EMPALMAN
/// se pintan en rojo y se pueden ARRASTRAR (mantener presionado) a otra celda
/// para reacomodarlas (petición de María). Reemplaza la antigua "nube de chips".
///
/// Es un widget "tonto": recibe las fechas de sesión, un predicado de empalme y
/// un callback de movimiento; el armador (padre) es dueño del estado y de la
/// lógica de conflictos (contra Acuity y contra las propias sesiones).
class WeekScheduler extends StatefulWidget {
  /// Fechas/hora de cada sesión (índice = identidad de la sesión).
  final List<DateTime> sessions;

  /// ¿La sesión en [index] se empalma con otra o con el calendario?
  final bool Function(int index) isConflict;

  /// El usuario soltó la sesión [index] en un nuevo día/hora.
  final void Function(int index, DateTime newStart) onMove;

  const WeekScheduler({
    super.key,
    required this.sessions,
    required this.isConflict,
    required this.onMove,
  });

  @override
  State<WeekScheduler> createState() => _WeekSchedulerState();
}

const _kDias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _kMeses = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _mondayOf(DateTime d) =>
    _dateOnly(d).subtract(Duration(days: d.weekday - 1));
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _WeekSchedulerState extends State<WeekScheduler> {
  late DateTime _weekStart; // lunes 00:00 de la semana visible

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(_earliestOrToday());
  }

  @override
  void didUpdateWidget(WeekScheduler old) {
    super.didUpdateWidget(old);
    // Si al regenerarse las sesiones ya no hay ninguna en la semana visible
    // pero sí existen sesiones, salta a la semana de la primera.
    if (widget.sessions.isNotEmpty && _sessionIndicesInWeek().isEmpty) {
      _weekStart = _mondayOf(_earliestOrToday());
    }
  }

  DateTime _earliestOrToday() {
    if (widget.sessions.isEmpty) return DateTime.now();
    return widget.sessions.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  List<int> _sessionIndicesInWeek() {
    final end = _weekStart.add(const Duration(days: 7));
    final out = <int>[];
    for (var i = 0; i < widget.sessions.length; i++) {
      final s = widget.sessions[i];
      if (!s.isBefore(_weekStart) && s.isBefore(end)) out.add(i);
    }
    return out;
  }

  // Rango de horas visible: acota a 7..19 pero se expande para incluir todas
  // las sesiones de la semana (p. ej. una sesión a las 6:00 o 21:00).
  (int, int) _hourRange(List<int> idx) {
    var lo = 7, hi = 19;
    for (final i in idx) {
      final h = widget.sessions[i].hour;
      if (h < lo) lo = h;
      if (h > hi) hi = h;
    }
    return (lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    final weekIdx = _sessionIndicesInWeek();
    final (loH, hiH) = _hourRange(weekIdx);
    final days = [for (var d = 0; d < 7; d++) _weekStart.add(Duration(days: d))];
    final total = widget.sessions.length;
    final conflictsHere = weekIdx.where(widget.isConflict).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Navegación de semana.
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Semana anterior',
              onPressed: () => setState(() =>
                  _weekStart = _weekStart.subtract(const Duration(days: 7))),
            ),
            Expanded(
              child: Text(
                _weekLabel(days.first, days.last),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Semana siguiente',
              onPressed: () => setState(
                  () => _weekStart = _weekStart.add(const Duration(days: 7))),
            ),
          ],
        ),
        Text(
          '${weekIdx.length} de $total sesión(es) en esta semana'
          '${conflictsHere > 0 ? ' · $conflictsHere empalmada(s)' : ''}',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              color: conflictsHere > 0
                  ? KuraColors.danger
                  : KuraColors.darkText.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 8),
        // Encabezado de días.
        Row(
          children: [
            const SizedBox(width: 40),
            for (final d in days)
              Expanded(
                child: Column(
                  children: [
                    Text(_kDias[d.weekday - 1],
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600)),
                    Text('${d.day}',
                        style: TextStyle(
                            fontSize: 11,
                            color: KuraColors.darkText.withValues(alpha: 0.6))),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        // Rejilla de horas.
        for (var h = loH; h <= hiH; h++) _hourRow(h, days),
        const SizedBox(height: 4),
        Text(
          'Mantén presionada una sesión y arrástrala a otro día/hora para '
          'reacomodar los empalmes (en rojo).',
          style: TextStyle(
              fontSize: 11,
              color: KuraColors.darkText.withValues(alpha: 0.55)),
        ),
      ],
    );
  }

  Widget _hourRow(int hour, List<DateTime> days) {
    return Row(
      // OJO: sin `CrossAxisAlignment.stretch`. Este widget vive dentro de un
      // ListView, donde la altura disponible es ILIMITADA; `stretch` obliga a
      // los hijos a alto infinito y toda la rejilla desaparece (en release no
      // hay assert, solo pantalla en blanco). Las celdas ya traen `height: 34`,
      // así que quedan alineadas con el default (center) sin stretch.
      children: [
        SizedBox(
          width: 40,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: Text('${hour.toString().padLeft(2, '0')}:00',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 10,
                    color: KuraColors.darkText.withValues(alpha: 0.5))),
          ),
        ),
        for (final day in days) Expanded(child: _cell(day, hour)),
      ],
    );
  }

  Widget _cell(DateTime day, int hour) {
    final items = <int>[];
    for (var i = 0; i < widget.sessions.length; i++) {
      final s = widget.sessions[i];
      if (_sameDay(s, day) && s.hour == hour) items.add(i);
    }
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        final i = d.data;
        final orig = widget.sessions[i];
        widget.onMove(
            i, DateTime(day.year, day.month, day.day, hour, orig.minute));
      },
      builder: (ctx, cand, rej) {
        final hovering = cand.isNotEmpty;
        return Container(
          height: 34,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: hovering
                ? KuraColors.primary.withValues(alpha: 0.18)
                : KuraColors.darkText.withValues(alpha: 0.02),
            border: Border.all(
                color: KuraColors.darkText.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: items.isEmpty
              ? null
              : Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [for (final i in items) _pill(i)],
                ),
        );
      },
    );
  }

  Widget _pill(int index) {
    final s = widget.sessions[index];
    final conflict = widget.isConflict(index);
    final c = conflict ? KuraColors.danger : KuraColors.primary;
    final label = '${s.hour.toString().padLeft(2, '0')}:'
        '${s.minute.toString().padLeft(2, '0')}';
    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (conflict) ...[
            const Icon(Icons.warning_amber_rounded,
                size: 10, color: KuraColors.danger),
            const SizedBox(width: 2),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: c,
                  fontWeight: conflict ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
    return LongPressDraggable<int>(
      data: index,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: pill),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: pill),
      child: pill,
    );
  }

  String _weekLabel(DateTime a, DateTime b) {
    final ma = _kMeses[a.month - 1];
    final mb = _kMeses[b.month - 1];
    if (a.month == b.month) {
      return '${a.day}–${b.day} $ma ${a.year}';
    }
    return '${a.day} $ma – ${b.day} $mb ${b.year}';
  }
}
