import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Convierte cualquier imagen que el NAVEGADOR pueda decodificar a JPEG,
/// re-escalando a [maxDim] px por lado. Clave para la clínica: el Safari de
/// iPhone decodifica HEIC/HEIF, así que esto convierte esas fotos a JPG —un
/// formato que Flutter y Storage manejan— sin pedirle al usuario cambiar nada.
///
/// Usa `createImageBitmap` (decodificador nativo del navegador) → canvas →
/// `toBlob('image/jpeg')`. Devuelve null si el navegador no puede decodificar
/// el formato (p. ej. HEIC en un Chrome de escritorio) o si algo falla; el
/// llamador decide el fallback (mostrar aviso / usar bytes originales).
Future<Uint8List?> transcodeImageToJpeg(
  Uint8List bytes, {
  String? name,
  int maxDim = 1600,
  double quality = 0.85,
}) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS);
    final web.ImageBitmap bitmap =
        await web.window.createImageBitmap(blob).toDart;

    var w = bitmap.width;
    var h = bitmap.height;
    final maxSide = w > h ? w : h;
    if (maxSide > maxDim && maxSide > 0) {
      final scale = maxDim / maxSide;
      w = (w * scale).round();
      h = (h * scale).round();
    }
    if (w <= 0 || h <= 0) {
      bitmap.close();
      return null;
    }

    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = w;
    canvas.height = h;
    final ctx =
        canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) {
      bitmap.close();
      return null;
    }
    ctx.drawImage(bitmap, 0, 0, w.toDouble(), h.toDouble());
    bitmap.close();

    final completer = Completer<Uint8List?>();
    void handleBlob(web.Blob? out) {
      if (out == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      out.arrayBuffer().toDart.then((buf) {
        if (!completer.isCompleted) {
          completer.complete(buf.toDart.asUint8List());
        }
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      });
    }

    canvas.toBlob(
      ((web.Blob? out) => handleBlob(out)).toJS,
      'image/jpeg',
      quality.toJS,
    );

    // Salvaguarda: si toBlob nunca llama de vuelta, no colgar el flujo.
    return completer.future.timeout(const Duration(seconds: 20),
        onTimeout: () => null);
  } catch (_) {
    return null;
  }
}
