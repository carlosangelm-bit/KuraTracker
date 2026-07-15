// ignore_for_file: dangling_library_doc_comments
/// Descarga un archivo CSV en el dispositivo/navegador del usuario.
///
/// En Flutter Web usa Blob + `<a download>` (ver csv_download_web.dart),
/// porque `file_picker.saveFile()` NO esta implementado en esa
/// plataforma. En Android/iOS/desktop usa el dialogo nativo de
/// `file_picker.saveFile()` (ver csv_download_io.dart). El punto de
/// entrada `downloadCsv()` es identico en ambos casos para que las
/// pantallas (p.ej. _NoteCatalogTab) no necesiten saber cual
/// implementacion esta activa.
export 'csv_download_stub.dart'
    if (dart.library.js_interop) 'csv_download_web.dart'
    if (dart.library.io) 'csv_download_io.dart';
