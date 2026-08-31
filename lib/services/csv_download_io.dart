import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Implementacion para plataformas nativas (Android/iOS/desktop): a
/// diferencia de Flutter Web, aqui `file_picker` SI implementa
/// `saveFile()` con un dialogo nativo de "Guardar como". Se usa en vez
/// del helper Blob+anchor (que es especifico de navegador).
Future<void> downloadCsv(String filename, String csvContent) async {
  await FilePicker.platform.saveFile(
    fileName: filename,
    bytes: Uint8List.fromList(csvContent.codeUnits),
  );
}

/// Descarga binaria (ZIP, imagen…) en nativo vía "Guardar como".
Future<void> downloadBytes(
    String filename, List<int> bytes, String mimeType) async {
  await FilePicker.platform.saveFile(
    fileName: filename,
    bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
  );
}
