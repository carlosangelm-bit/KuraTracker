import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Implementacion real (Flutter Web) de la descarga de un archivo CSV.
///
/// `file_picker` (paquete ya usado en el proyecto para CARGAR CSV, ver
/// import_export_screen.dart) NO implementa `saveFile()` en Flutter Web
/// (confirmado inspeccionando `FilePickerWeb`: solo sobreescribe
/// `pickFiles`), asi que para "descargar plantilla CSV" (Configuracion >
/// catalogo de la nota de seguimiento) se usa el patron estandar del
/// navegador: Blob + URL.createObjectURL + <a download> + click()
/// programatico, via `package:web` (dependencia transitiva ya presente,
/// ver .dart_tool/package_config.json).
Future<void> downloadCsv(String filename, String csvContent) async {
  // BOM UTF-8 al inicio para que Excel/Sheets no rompan los acentos
  // (tildes, ñ) del catalogo al abrir el CSV descargado.
  const bom = '\uFEFF';
  final blob = web.Blob(
    [(bom + csvContent).toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8;'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// Descarga binaria (ZIP, imagen…) en el navegador: Blob + `<a download>`.
Future<void> downloadBytes(
    String filename, List<int> bytes, String mimeType) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final blob =
      web.Blob([data.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
