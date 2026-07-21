import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Controlador de una firma trazada (vector, sin imágenes/binarios). Guarda los
/// trazos como listas de puntos en el espacio local del pad, junto al tamaño de
/// captura, para poder re-escalarlos al mostrarlos. Serializa a JSON de texto,
/// que es lo que se persiste en consultations.follow_up_signature (0027).
///
/// Lógica pura (sin dependencias de tema): vive aparte de signature_pad.dart
/// para poder testearse sin arrastrar el tema de la app.
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _canvasSize = Size.zero;

  List<List<Offset>> get strokes => _strokes;
  bool get isEmpty => _strokes.every((s) => s.length < 2);
  bool get isNotEmpty => !isEmpty;

  void setCanvasSize(Size size) => _canvasSize = size;

  void startStroke(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void appendPoint(Offset p) {
    if (_strokes.isEmpty) _strokes.add([]);
    _strokes.last.add(p);
    notifyListeners();
  }

  void endStroke() => notifyListeners();

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// Serializa la firma a JSON de texto. Devuelve null si está vacía.
  String? toJsonString() {
    if (isEmpty) return null;
    return jsonEncode({
      'w': _canvasSize.width,
      'h': _canvasSize.height,
      'strokes':
          _strokes.map((s) => s.map((p) => [p.dx, p.dy]).toList()).toList(),
    });
  }
}

/// Datos de una firma para renderizado de solo lectura (parseados del JSON
/// persistido). [strokes] en el espacio de captura de tamaño [size].
class SignatureData {
  final List<List<Offset>> strokes;
  final Size size;
  const SignatureData(this.strokes, this.size);

  static SignatureData? tryParse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final w = (map['w'] as num?)?.toDouble() ?? 0;
      final h = (map['h'] as num?)?.toDouble() ?? 0;
      final strokes = (map['strokes'] as List)
          .map((s) => (s as List)
              .map((p) => Offset(
                    (p[0] as num).toDouble(),
                    (p[1] as num).toDouble(),
                  ))
              .toList())
          .toList();
      if (strokes.isEmpty) return null;
      return SignatureData(strokes, Size(w, h));
    } catch (_) {
      return null;
    }
  }
}
