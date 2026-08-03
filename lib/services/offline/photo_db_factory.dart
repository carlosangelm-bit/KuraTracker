// ignore_for_file: dangling_library_doc_comments
/// Selección por plataforma del `DatabaseFactory` de sembast para la cola de
/// fotos: IndexedDB en Web (producción), memoria en el resto (VM/tests). El
/// import condicional evita arrastrar `sembast_web` (web-only) a la
/// compilación de VM/tests.
export 'photo_db_factory_memory.dart'
    if (dart.library.js_interop) 'photo_db_factory_web.dart';
