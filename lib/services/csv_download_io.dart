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
