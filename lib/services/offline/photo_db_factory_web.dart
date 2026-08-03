import 'package:sembast_web/sembast_web.dart';

/// Producción (Flutter Web): las fotos pendientes se persisten en IndexedDB
/// (los blobs no caben en localStorage/SharedPreferences).
DatabaseFactory getPhotoDbFactory() => databaseFactoryWeb;
