import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Puente a la función JS `window.convertHeicToJpeg(blob, quality)` definida en
/// web/index.html (heic2any). Convierte un HEIC/HEIF a un Blob JPEG usando el
/// decodificador HEIF propio de la librería, para los navegadores que NO
/// decodifican HEIC de forma nativa (Chrome de escritorio, Android). Si el
/// script no cargó, invocarla lanza y el llamador cae al comportamiento previo.
@JS('convertHeicToJpeg')
external JSPromise<web.Blob> _convertHeicToJpeg(web.Blob blob, double quality);

/// Decodifica [blob] a un ImageBitmap. Primero intenta el decodificador nativo
/// del navegador (rápido; cubre JPEG/PNG/WebP y HEIC en Safari iOS). Si falla
/// —típico con HEIC en Chrome/Android— reintenta convirtiendo con heic2any.
Future<web.ImageBitmap?> _decodeToBitmap(web.Blob blob, String? name) async {
  try {
    return await web.window.createImageBitmap(blob).toDart;
  } catch (_) {
    // El navegador no pudo decodificar. Intentar heic2any (HEIC/HEIF).
    try {
      final jpegBlob = await _convertHeicToJpeg(blob, 0.9).toDart;
      return await web.window.createImageBitmap(jpegBlob).toDart;
    } catch (_) {
      return null;
    }
  }
}

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
    final web.ImageBitmap? bitmap = await _decodeToBitmap(blob, name);
    if (bitmap == null) return null;

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
