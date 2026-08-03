import 'package:sembast/sembast_memory.dart';

/// Fallback (VM / tests / plataformas no-web): base de datos en memoria. En
/// producción la app es Flutter Web y usa IndexedDB (ver photo_db_factory_web).
DatabaseFactory getPhotoDbFactory() => databaseFactoryMemory;
