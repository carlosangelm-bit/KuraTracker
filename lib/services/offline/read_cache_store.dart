import 'package:sembast/sembast.dart';

import 'photo_db_factory.dart' show getPhotoDbFactory;

/// Persistencia de la caché de LECTURA (offline-first, Fase 3). Guarda en
/// IndexedDB (Web) el resultado de `hydrate()` —una lista de filas por
/// colección— para que los expedientes puedan verse SIN señal (al abrir/
/// recargar la app offline) y no solo en la sesión en memoria.
///
/// Nota de privacidad: contiene datos clínicos ya filtrados por RLS (lo que el
/// usuario podía ver). Se BORRA en el logout (ver DataRepository) para que otro
/// usuario en el mismo dispositivo no vea el expediente del anterior.
class ReadCacheStore {
  static const _dbName = 'kura_read_cache.db';

  final Database _db;
  // key = nombre de colección; value = List<Map> (filas), JSON-compatible.
  final StoreRef<String, Object?> _store;

  ReadCacheStore._(this._db, this._store);

  static Future<ReadCacheStore> open() async {
    // Reutiliza el factory de sembast por plataforma (IndexedDB web / memoria
    // en VM/tests) que ya usa la cola de fotos.
    final db = await getPhotoDbFactory().openDatabase(_dbName);
    return ReadCacheStore._(db, StoreRef<String, Object?>.main());
  }

  /// Carga toda la caché persistida: {colección: filas}.
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async {
    final records = await _store.find(_db);
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in records) {
      final raw = r.value;
      if (raw is List) {
        out[r.key] = raw
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    }
    return out;
  }

  /// Persiste una sola colección (tras una escritura/refresh que mutó la caché).
  Future<void> saveCollection(
      String collection, List<Map<String, dynamic>> rows) async {
    await _store.record(collection).put(_db, rows);
  }

  /// Persiste todas las colecciones de una vez (tras un `hydrate()` completo).
  Future<void> saveAll(Map<String, List<Map<String, dynamic>>> cache) async {
    await _db.transaction((txn) async {
      for (final e in cache.entries) {
        await _store.record(e.key).put(txn, e.value);
      }
    });
  }

  /// Borra toda la caché persistida (logout).
  Future<void> clear() async {
    await _store.delete(_db);
  }
}
