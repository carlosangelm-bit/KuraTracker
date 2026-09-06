import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../../core/theme/kura_theme.dart';
import '../../../engine/vision/vision_geometry.dart';
import '../../../engine/vision/vision_params.dart';
import '../../../engine/vision/wound_vision_engine.dart';

/// Lo que la pantalla devuelve al formulario cuando el clínico pulsa
/// «Aplicar a la valoración».
class WoundVisionApplyResult {
  final WoundVisionResult result;
  final Uint8List rectifiedPng;
  final Uint8List overlayPng;
  const WoundVisionApplyResult({
    required this.result,
    required this.rectifiedPng,
    required this.overlayPng,
  });

  /// Largo/ancho redondeados a 0,1 cm como los captura el clínico con regla.
  double get lengthCm => (result.measurement.lengthCm * 10).round() / 10;
  double get widthCm => (result.measurement.widthCm * 10).round() / 10;

  /// Etiqueta legible del modo de calibración (tarjeta / disco), en minúsculas.
  String get modeLabel => result.calibration.mode.label.toLowerCase();
}

/// Pantalla «Medir con foto»: calibra la foto (tarjeta WoundCalibrate o
/// disco), deja que el clínico toque la herida (o la trace a mano), y muestra
/// área, largo, ancho, perímetro y composición del lecho para aplicarlos al
/// formulario. Todo corre en el dispositivo; la foto no sale de él.
class WoundVisionScreen extends StatefulWidget {
  final Uint8List photoBytes;

  const WoundVisionScreen({super.key, required this.photoBytes});

  /// Abre la pantalla y devuelve el resultado aplicado (o null si se canceló).
  static Future<WoundVisionApplyResult?> open(BuildContext context, Uint8List photoBytes) {
    return Navigator.of(context).push<WoundVisionApplyResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WoundVisionScreen(photoBytes: photoBytes),
      ),
    );
  }

  @override
  State<WoundVisionScreen> createState() => _WoundVisionScreenState();
}

enum _Mode { auto, manual }

class _WoundVisionScreenState extends State<WoundVisionScreen> {
  WoundVisionEngine? _engine;
  CalibrationOutcome? _calibration;
  WoundVisionResult? _result;
  String? _error;
  bool _busy = true;
  String _busyLabel = 'Buscando la referencia de escala…';
  _Mode _mode = _Mode.auto;
  final List<Pt> _seeds = [];
  final List<Pt> _trace = [];
  double _sensitivity = 0.5;
  bool _showTissue = true;
  // El paso de marcar/trazar se abre a PANTALLA COMPLETA (imagen al máximo, con
  // zoom y desplazamiento); las medidas y «Aplicar» aparecen al salir de él.
  bool _tracing = true;
  final TransformationController _tc = TransformationController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final (spec, params) = await VisionAssets.load();
      final engine = WoundVisionEngine(spec: spec, params: params);
      _sensitivity = params.sensitivityDefault;
      final outcome = await compute(_calibrateTask, _CalibrateArgs(engine, widget.photoBytes));
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _calibration = outcome;
        _busy = false;
        if (outcome.result == null) _error = outcome.failure?.message ?? 'No se pudo calibrar la foto.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Error al procesar la foto: $e';
      });
    }
  }

  Future<void> _reanalyze() async {
    final engine = _engine, cal = _calibration;
    if (engine == null || cal == null || cal.result == null) return;
    if (_mode == _Mode.auto && _seeds.isEmpty) {
      setState(() => _result = null);
      return;
    }
    if (_mode == _Mode.manual && _trace.length < 3) {
      setState(() => _result = null);
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = _mode == _Mode.auto ? 'Delimitando la herida…' : 'Midiendo el contorno…';
    });
    try {
      final res = await compute(
        _analyzeTask,
        _AnalyzeArgs(
          engine: engine,
          calibration: cal,
          seeds: _mode == _Mode.auto ? List<Pt>.from(_seeds) : const [],
          trace: _mode == _Mode.manual ? List<Pt>.from(_trace) : const [],
          sensitivity: _sensitivity,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _busy = false;
        if (res == null && _mode == _Mode.auto) {
          _error = 'No se pudo delimitar la herida desde ese punto. Toca de nuevo dentro de la herida o traza el contorno a mano.';
        } else {
          _error = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Error al analizar: $e';
      });
    }
  }

  void _onTap(Pt imagePx) {
    final cal = _calibration?.result;
    if (cal == null || _busy) return;
    if (imagePx.x < 0 || imagePx.y < 0 || imagePx.x >= cal.width || imagePx.y >= cal.height) return;
    setState(() {
      if (_mode == _Mode.auto) {
        _seeds.add(imagePx);
      } else {
        _trace.add(imagePx);
      }
    });
    _reanalyze();
  }

  void _undo() {
    setState(() {
      if (_mode == _Mode.auto) {
        if (_seeds.isNotEmpty) _seeds.removeLast();
      } else {
        if (_trace.isNotEmpty) _trace.removeLast();
      }
    });
    _reanalyze();
  }

  void _clear() {
    setState(() {
      _seeds.clear();
      _trace.clear();
      _result = null;
      _error = null;
    });
  }

  void _apply() {
    final res = _result, cal = _calibration?.result;
    if (res == null || cal == null) return;
    Navigator.of(context).pop(WoundVisionApplyResult(
      result: res,
      rectifiedPng: cal.rectifiedPng,
      overlayPng: res.overlayPng,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cal = _calibration?.result;
    if (cal == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Medir con foto')),
        body: _buildCalibrating(),
      );
    }
    return _tracing ? _buildTracing(context, cal) : _buildResults(context, cal);
  }

  // ---------------------------------------------------------------------------
  // FASE 1 · TRAZADO a pantalla completa: la foto ocupa todo el alto disponible,
  // con zoom (pellizco) y desplazamiento (arrastre) para ajustar el borde con
  // precisión. Los controles flotan SOBRE la imagen (no le quitan espacio). El
  // botón «Ver medidas» sale del modo de trazado a la fase de resultados.
  // ---------------------------------------------------------------------------
  Widget _buildTracing(BuildContext context, CalibrationResult cal) {
    final hint = _mode == _Mode.auto
        ? 'Toca DENTRO de la herida; pellizca para acercar y arrastra para mover. Si tiene varios tejidos, toca cada uno.'
        : 'Toca los puntos del contorno en orden (mínimo 3); se cierra solo. Pellizca para acercar y arrastra para mover.';
    return Scaffold(
      backgroundColor: const Color(0xFF141118),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildInteractiveImage(cal)),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
            // Barra superior flotante: cerrar · modo · tejido · deshacer · limpiar.
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: _overlayBar(
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    SegmentedButton<_Mode>(
                      segments: const [
                        ButtonSegment(
                            value: _Mode.auto,
                            icon: Icon(Icons.touch_app_outlined),
                            tooltip: 'Tocar la herida'),
                        ButtonSegment(
                            value: _Mode.manual,
                            icon: Icon(Icons.gesture),
                            tooltip: 'Trazar a mano'),
                      ],
                      selected: {_mode},
                      showSelectedIcon: false,
                      onSelectionChanged: _busy
                          ? null
                          : (s) {
                              setState(() {
                                _mode = s.first;
                                _result = null;
                                _error = null;
                              });
                              _reanalyze();
                            },
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: _showTissue ? 'Ocultar tejido' : 'Ver tejido',
                      icon: Icon(_showTissue ? Icons.layers : Icons.layers_clear_outlined,
                          color: Colors.white),
                      onPressed: () => setState(() => _showTissue = !_showTissue),
                    ),
                    IconButton(
                      tooltip: 'Deshacer último punto',
                      onPressed: _busy || (_mode == _Mode.auto ? _seeds.isEmpty : _trace.isEmpty)
                          ? null
                          : _undo,
                      icon: const Icon(Icons.undo, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'Limpiar',
                      onPressed: _busy || (_seeds.isEmpty && _trace.isEmpty) ? null : _clear,
                      icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            // Barra inferior flotante: sensibilidad (auto) · pista · «Ver medidas».
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: _overlayBar(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_mode == _Mode.auto)
                      Row(
                        children: [
                          const Text('Sensibilidad',
                              style: TextStyle(fontSize: 12, color: Colors.white70)),
                          Expanded(
                            child: Slider(
                              value: _sensitivity,
                              min: 0,
                              max: 1,
                              divisions: 10,
                              label: _sensitivity < 0.5
                                  ? 'Más estricta'
                                  : (_sensitivity > 0.5 ? 'Más amplia' : 'Neutra'),
                              onChanged: _busy ? null : (v) => setState(() => _sensitivity = v),
                              onChangeEnd: (_) => _reanalyze(),
                            ),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(_error ?? hint,
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _result == null || _busy
                              ? null
                              : () => setState(() => _tracing = false),
                          icon: const Icon(Icons.straighten),
                          label: const Text('Ver medidas'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlayBar({required Widget child}) => Material(
        color: const Color(0xCC1E1B26),
        borderRadius: BorderRadius.circular(14),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: child,
        ),
      );

  /// Imagen rectificada + tejido + marcas dentro de un [InteractiveViewer]
  /// (zoom/pan). El [GestureDetector] va DENTRO del hijo del viewer, así que su
  /// `localPosition` llega en coordenadas del hijo SIN transformar por el zoom:
  /// el mapeo toque→píxel (y por tanto la calibración) se conserva intacto.
  Widget _buildInteractiveImage(CalibrationResult cal) {
    final res = _result;
    return LayoutBuilder(builder: (context, c) {
      // Ajuste tipo BoxFit.contain calculado a mano para mapear toques → px.
      final scale = math.min(c.maxWidth / cal.width, c.maxHeight / cal.height);
      final dw = cal.width * scale, dh = cal.height * scale;
      final ox = (c.maxWidth - dw) / 2, oy = (c.maxHeight - dh) / 2;
      return InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 10,
        boundaryMargin: const EdgeInsets.all(120),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final lx = (d.localPosition.dx - ox) / scale, ly = (d.localPosition.dy - oy) / scale;
            _onTap(Pt(lx, ly));
          },
          child: Stack(
            children: [
              Positioned(
                left: ox,
                top: oy,
                width: dw,
                height: dh,
                child: Image.memory(cal.rectifiedPng, fit: BoxFit.fill, gaplessPlayback: true),
              ),
              if (res != null && _showTissue)
                Positioned(
                  left: ox,
                  top: oy,
                  width: dw,
                  height: dh,
                  child: Image.memory(res.overlayPng, fit: BoxFit.fill, gaplessPlayback: true),
                ),
              Positioned(
                left: ox,
                top: oy,
                width: dw,
                height: dh,
                child: CustomPaint(
                  painter: _MarksPainter(
                    seeds: _mode == _Mode.auto ? _seeds : const [],
                    trace: _mode == _Mode.manual ? _trace : const [],
                    scale: scale,
                    excluded: cal.excludedRects,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // FASE 2 · RESULTADOS: medidas, composición del lecho, calidad y «Aplicar».
  // Una vista previa con «Editar contorno» reabre la fase de trazado.
  // ---------------------------------------------------------------------------
  Widget _buildResults(BuildContext context, CalibrationResult cal) {
    final gates = _result?.gates ?? cal.gates;
    return Scaffold(
      appBar: AppBar(title: const Text('Medir con foto')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _resultPreview(cal),
            const SizedBox(height: 12),
            _buildMetrics(cal, gates),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Apoyo a la decisión clínica — no sustituye el juicio clínico. '
                  'Revisa y ajusta las medidas antes de guardar.',
                  style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.6)),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _result == null || _busy ? null : _apply,
                icon: const Icon(Icons.check),
                label: const Text('Aplicar a la valoración'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultPreview(CalibrationResult cal) {
    final res = _result;
    return Container(
      decoration:
          BoxDecoration(color: const Color(0xFF1E1B26), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(cal.rectifiedPng, fit: BoxFit.contain, gaplessPlayback: true),
                if (res != null && _showTissue)
                  Image.memory(res.overlayPng, fit: BoxFit.contain, gaplessPlayback: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _tracing = true),
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  label: Text(_mode == _Mode.auto ? 'Editar / marcar' : 'Editar contorno',
                      style: const TextStyle(color: Colors.white)),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _showTissue ? 'Ocultar tejido' : 'Ver tejido',
                  icon: Icon(_showTissue ? Icons.layers : Icons.layers_clear_outlined,
                      color: Colors.white70),
                  onPressed: () => setState(() => _showTissue = !_showTissue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrating() {
    if (_busy) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_busyLabel),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner, size: 48, color: KuraColors.warning),
            const SizedBox(height: 12),
            Text(_error ?? 'No se encontró una referencia de escala.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Para medir en centímetros la foto debe incluir la tarjeta de calibración '
              'WoundCalibrate (plana, completa y sin reflejos) o el disco de referencia verde, '
              'junto a la herida y en el mismo plano. Coloca la tarjeta ALINEADA con el eje '
              'cabeza-pies del paciente: así el largo se mide en ese eje y el ancho a lo ancho.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver')),
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics(CalibrationResult cal, List<QualityGate> gates) {
    final res = _result;
    final m = res?.measurement;
    final t = res?.tissue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(cal.mode == CalibrationMode.card ? Icons.qr_code_2 : Icons.circle_outlined, size: 18, color: KuraColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${cal.mode.label} · ${(cal.mmPerPx * 1000).toStringAsFixed(0)} µm/px',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: KuraColors.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_error!, style: const TextStyle(fontSize: 12)),
          ),
        if (m != null) ...[
          _MeasureGrid(measurement: m),
          const SizedBox(height: 12),
          if (t != null) _TissueBars(tissue: t),
          const SizedBox(height: 8),
          Text(
            'Área por planimetría: ${m.areaCm2.toStringAsFixed(2)} cm² · estimado por elipse (L × A × 0,785): '
            '${m.ellipseEstimateCm2.toStringAsFixed(2)} cm².',
            style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.6)),
          ),
          const SizedBox(height: 12),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Aún no hay medidas: usa «Editar contorno» para marcar o trazar la herida.',
              style: TextStyle(color: KuraColors.darkText.withOpacity(0.6)),
            ),
          ),
        const Text('Calidad de la captura', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final g in gates) _GateTile(gate: g),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Tareas (aptas para compute/isolate; en Web corren en el mismo hilo)
// -----------------------------------------------------------------------------

class _CalibrateArgs {
  final WoundVisionEngine engine;
  final Uint8List bytes;
  const _CalibrateArgs(this.engine, this.bytes);
}

CalibrationOutcome _calibrateTask(_CalibrateArgs a) => a.engine.calibratePhoto(a.bytes);

class _AnalyzeArgs {
  final WoundVisionEngine engine;
  final CalibrationOutcome calibration;
  final List<Pt> seeds;
  final List<Pt> trace;
  final double sensitivity;
  const _AnalyzeArgs({
    required this.engine,
    required this.calibration,
    required this.seeds,
    required this.trace,
    required this.sensitivity,
  });
}

WoundVisionResult? _analyzeTask(_AnalyzeArgs a) {
  if (a.trace.length >= 3) {
    return a.engine.analyzeManualTrace(a.calibration, polygon: a.trace);
  }
  return a.engine.analyze(a.calibration, seeds: a.seeds, sensitivity: a.sensitivity);
}

// -----------------------------------------------------------------------------
// Widgets auxiliares
// -----------------------------------------------------------------------------

class _MarksPainter extends CustomPainter {
  final List<Pt> seeds;
  final List<Pt> trace;
  final double scale;
  final List<RectD> excluded;
  const _MarksPainter({required this.seeds, required this.trace, required this.scale, required this.excluded});

  @override
  void paint(Canvas canvas, Size size) {
    final ex = Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.fill;
    for (final r in excluded) {
      canvas.drawRect(Rect.fromLTRB(r.x0 * scale, r.y0 * scale, r.x1 * scale, r.y1 * scale), ex);
    }
    final seedFill = Paint()..color = const Color(0xFF22C55E);
    final seedRing = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final s in seeds) {
      final o = Offset(s.x * scale, s.y * scale);
      canvas.drawCircle(o, 7, seedFill);
      canvas.drawCircle(o, 7, seedRing);
    }
    if (trace.isNotEmpty) {
      final line = Paint()
        ..color = const Color(0xFF7C3AED)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final path = Path()..moveTo(trace.first.x * scale, trace.first.y * scale);
      for (final p in trace.skip(1)) {
        path.lineTo(p.x * scale, p.y * scale);
      }
      if (trace.length >= 3) path.close();
      canvas.drawPath(path, line);
      final dot = Paint()..color = Colors.white;
      for (final p in trace) {
        canvas.drawCircle(Offset(p.x * scale, p.y * scale), 4, dot);
      }
    }
  }

  // Las listas de semillas/trazo son mutables y se comparten entre builds, así
  // que la comparación por identidad no detecta cambios: repintar siempre (es
  // una capa ligera).
  @override
  bool shouldRepaint(covariant _MarksPainter old) => true;
}

class _MeasureGrid extends StatelessWidget {
  final WoundMeasurementResult measurement;
  const _MeasureGrid({required this.measurement});

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: KuraColors.chipBg, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.6))),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
        );
    return Column(
      children: [
        Row(children: [
          cell('Largo', '${measurement.lengthCm.toStringAsFixed(1)} cm'),
          const SizedBox(width: 8),
          cell('Ancho', '${measurement.widthCm.toStringAsFixed(1)} cm'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          cell('Área', '${measurement.areaCm2.toStringAsFixed(2)} cm²'),
          const SizedBox(width: 8),
          cell('Perímetro', '${measurement.perimeterCm.toStringAsFixed(1)} cm'),
        ]),
      ],
    );
  }
}

class _TissueBars extends StatelessWidget {
  final TissueComposition tissue;
  const _TissueBars({required this.tissue});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Granulación', tissue.granulacion, KuraTissueColors.granulacion),
      ('Esfacelo', tissue.esfacelo, KuraTissueColors.esfacelo),
      ('Necrosis', tissue.necrosis, KuraTissueColors.necrosis),
      ('Epitelización', tissue.epitelizacion, KuraTissueColors.epitelizacion),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Composición del lecho (estimada)', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 100, child: Text(r.$1, style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (r.$2 / 100).clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: KuraColors.chipBg,
                      color: r.$3,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${r.$2.round()} %',
                      textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GateTile extends StatelessWidget {
  final QualityGate gate;
  const _GateTile({required this.gate});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (gate.status) {
      GateStatus.pass => (Icons.check_circle, KuraColors.success),
      GateStatus.warn => (Icons.warning_amber_rounded, KuraColors.warning),
      GateStatus.fail => (Icons.cancel, KuraColors.danger),
      GateStatus.skipped => (Icons.remove_circle_outline, KuraColors.darkText.withOpacity(0.35)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gate.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(gate.detail, style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
