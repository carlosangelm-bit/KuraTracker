/// Stub de fallback (no deberia usarse en runtime: Flutter siempre expone
/// dart.library.js_interop en Web o dart.library.io en nativo).
Future<void> downloadCsv(String filename, String csvContent) async {
  throw UnsupportedError('Descarga de CSV no soportada en esta plataforma.');
}
