/// Conversión de imágenes a JPEG, resuelta por plataforma (igual patrón que
/// csv_download): en Web usa el navegador (canvas) para decodificar y re-
/// exportar; en nativo cae al stub (no-op).
export 'image_transcode_stub.dart'
    if (dart.library.js_interop) 'image_transcode_web.dart';
