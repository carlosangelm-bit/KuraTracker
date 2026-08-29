import 'package:flutter/material.dart';

import '../../../models/wound.dart';

/// Editor estructurado de la DIRECCIÓN de socavamiento y tunelización (0093).
///
/// - Tunelización = PUNTO: "a las N, cm" (reloj 1–12).
/// - Socavamiento = ARCO: "de las N a las M, cm"; el arco puede cruzar las 12.
/// - Referencia: las **12 = cabeza del paciente**.
/// - Validación: reloj 1–12 (lo fija el selector) y profundidad > 0 (las filas
///   sin profundidad no se emiten). No se valida `from < to`.
///
/// Se muestra por tipo según [showTunneling]/[showUndermining] (el booleano de
/// la valoración). Emite las listas por [onChanged]; el padre las persiste.
class UnderminingTunnelingEditor extends StatefulWidget {
  final bool showTunneling;
  final bool showUndermining;
  final List<TunnelingSite> tunnelingSites;
  final List<UnderminingSite> underminingSites;
  final void Function(
    List<TunnelingSite> tunneling,
    List<UnderminingSite> undermining,
  ) onChanged;

  const UnderminingTunnelingEditor({
    super.key,
    required this.showTunneling,
    required this.showUndermining,
    required this.tunnelingSites,
    required this.underminingSites,
    required this.onChanged,
  });

  @override
  State<UnderminingTunnelingEditor> createState() =>
      _UnderminingTunnelingEditorState();
}

class _TunRow {
  int clock;
  final TextEditingController depth;
  _TunRow(this.clock, double d)
      : depth = TextEditingController(text: d > 0 ? _fmt(d) : '');
}

class _UndRow {
  int from;
  int to;
  final TextEditingController depth;
  _UndRow(this.from, this.to, double d)
      : depth = TextEditingController(text: d > 0 ? _fmt(d) : '');
}

String _fmt(double d) =>
    d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();

class _UnderminingTunnelingEditorState
    extends State<UnderminingTunnelingEditor> {
  late List<_TunRow> _tun;
  late List<_UndRow> _und;

  @override
  void initState() {
    super.initState();
    _tun = widget.tunnelingSites
        .map((s) => _TunRow(s.clock, s.depthCm))
        .toList();
    _und = widget.underminingSites
        .map((s) => _UndRow(s.clockFrom, s.clockTo, s.depthCm))
        .toList();
  }

  @override
  void dispose() {
    for (final r in _tun) {
      r.depth.dispose();
    }
    for (final r in _und) {
      r.depth.dispose();
    }
    super.dispose();
  }

  double _parse(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.')) ?? 0;

  void _emit() {
    final tun = <TunnelingSite>[
      for (final r in _tun)
        if (_parse(r.depth.text) > 0)
          TunnelingSite(clock: r.clock, depthCm: _parse(r.depth.text)),
    ];
    final und = <UnderminingSite>[
      for (final r in _und)
        if (_parse(r.depth.text) > 0)
          UnderminingSite(
              clockFrom: r.from, clockTo: r.to, depthCm: _parse(r.depth.text)),
    ];
    widget.onChanged(tun, und);
  }

  Widget _clockDropdown(int value, ValueChanged<int> onChanged) {
    return DropdownButton<int>(
      value: value,
      isDense: true,
      items: [
        for (var h = 1; h <= 12; h++)
          DropdownMenuItem(value: h, child: Text('$h')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _depthField(TextEditingController c) {
    return SizedBox(
      width: 70,
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          isDense: true,
          suffixText: 'cm',
          hintText: 'prof.',
        ),
        onChanged: (_) => _emit(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final note = Text(
      'Referencia del reloj: las 12 = cabeza del paciente.',
      style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTunneling || widget.showUndermining) ...[
          const SizedBox(height: 4),
          note,
        ],
        if (widget.showTunneling) ...[
          const SizedBox(height: 8),
          Text('Tunelización (trayecto: a las N, cm)',
              style: t.labelLarge),
          for (var i = 0; i < _tun.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Text('A las '),
                  _clockDropdown(_tun[i].clock, (v) {
                    setState(() => _tun[i].clock = v);
                    _emit();
                  }),
                  const SizedBox(width: 8),
                  _depthField(_tun[i].depth),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Quitar',
                    onPressed: () {
                      setState(() {
                        _tun[i].depth.dispose();
                        _tun.removeAt(i);
                      });
                      _emit();
                    },
                  ),
                ],
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar trayecto'),
            onPressed: () => setState(() => _tun.add(_TunRow(12, 0))),
          ),
        ],
        if (widget.showUndermining) ...[
          const SizedBox(height: 8),
          Text('Socavamiento (arco: de las N a las M, cm)',
              style: t.labelLarge),
          for (var i = 0; i < _und.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Text('De '),
                  _clockDropdown(_und[i].from, (v) {
                    setState(() => _und[i].from = v);
                    _emit();
                  }),
                  const Text(' a '),
                  _clockDropdown(_und[i].to, (v) {
                    setState(() => _und[i].to = v);
                    _emit();
                  }),
                  const SizedBox(width: 8),
                  _depthField(_und[i].depth),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Quitar',
                    onPressed: () {
                      setState(() {
                        _und[i].depth.dispose();
                        _und.removeAt(i);
                      });
                      _emit();
                    },
                  ),
                ],
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar arco'),
            onPressed: () => setState(() => _und.add(_UndRow(12, 3, 0))),
          ),
        ],
      ],
    );
  }
}
