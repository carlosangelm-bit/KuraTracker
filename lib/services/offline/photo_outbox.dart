import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import 'photo_db_factory.dart';

/// Una foto pendiente de subir (capturada sin red). Los bytes se guardan en
/// IndexedDB (Web); `meta` lleva los campos para crear la fila `wound_photos`
/// una vez subida (wound_id, consultation_id, measurement_id, is_baseline,
/// photo_stage, taken_at).
class PendingPhoto {
  final String localId;
  final String fileName;
  final String contentType;
  final Uint8List bytes;
  final Map<String, dynamic> meta;
  final int attempts;

  const PendingPhoto({
    required this.localId,
    required this.fileName,
    required this.contentType,
    required this.bytes,
    required this.meta,
    this.attempts = 0,
  });
}

/// Cola persistente de FOTOS offline (Fase 2). Respaldada por sembast:
/// IndexedDB en Web (producción), memoria en VM/tests. Los blobs se guardan en
/// base64 (JSON-safe); IndexedDB tiene cuota amplia (a diferencia de
/// localStorage), suficiente para varias fotos pendientes.
class PhotoOutbox {
  static const _dbName = 'kura_offline_photos.db';

  /// Reintentos ante rechazo no-transitorio antes de "parkear" (Fase 4).
  static const maxAttempts = 5;

  final Database _db;
  final StoreRef<String, Map<String, Object?>> _store;

  /// Fotos por subir (intentos < maxAttempts).
  final ValueNotifier<int> pendingCount;

  /// Fotos parkeadas (fallo persistente) que requieren atención.
  final ValueNotifier<int> failedCount;

  PhotoOutbox._(this._db, this._store)
      : pendingCount = ValueNotifier<int>(0),
        failedCount = ValueNotifier<int>(0);

  static Future<PhotoOutbox> open() async {
    final db = await getPhotoDbFactory().openDatabase(_dbName);
    final store = stringMapStoreFactory.store('pending_photos');
    final box = PhotoOutbox._(db, store);
    await box._refreshCounts();
    return box;
  }

  int get length => pendingCount.value + failedCount.value;
  bool get isEmpty => length == 0;

  Future<void> enqueue(PendingPhoto p, {required String createdAt}) async {
    await _store.record(p.localId).put(_db, {
      'file_name': p.fileName,
      'content_type': p.contentType,
      'bytes_b64': base64Encode(p.bytes),
      'meta': p.meta,
      'attempts': p.attempts,
      'created_at': createdAt,
    });
    await _refreshCounts();
  }

  PendingPhoto _fromRecord(RecordSnapshot<String, Map<String, Object?>> r) {
    final v = r.value;
    return PendingPhoto(
      localId: r.key,
      fileName: v['file_name'] as String,
      contentType: v['content_type'] as String,
      bytes: base64Decode(v['bytes_b64'] as String),
      meta: (v['meta'] as Map).cast<String, dynamic>(),
      attempts: (v['attempts'] as num?)?.toInt() ?? 0,
    );
  }

  /// Fotos por intentar subir (no parkeadas), en orden.
  Future<List<PendingPhoto>> pending() async {
    final records = await _store.find(
      _db,
      finder: Finder(
        filter: Filter.lessThan('attempts', maxAttempts),
        sortOrders: [SortOrder('created_at')],
      ),
    );
    return records.map(_fromRecord).toList();
  }

  /// Fotos parkeadas (fallo persistente).
  Future<List<PendingPhoto>> failed() async {
    final records = await _store.find(
      _db,
      finder: Finder(
        filter: Filter.greaterThanOrEquals('attempts', maxAttempts),
        sortOrders: [SortOrder('created_at')],
      ),
    );
    return records.map(_fromRecord).toList();
  }

  Future<void> remove(String localId) async {
    await _store.record(localId).delete(_db);
    await _refreshCounts();
  }

  Future<void> markFailed(String localId, String error) async {
    final rec = _store.record(localId);
    final cur = await rec.get(_db);
    if (cur == null) return;
    await rec.put(_db, {
      ...cur,
      'attempts': ((cur['attempts'] as num?)?.toInt() ?? 0) + 1,
      'last_error': error,
    });
    await _refreshCounts();
  }

  /// Descarta (borra) las fotos parkeadas.
  Future<void> discardFailed() async {
    final failedRecs = await _store.find(
      _db,
      finder:
          Finder(filter: Filter.greaterThanOrEquals('attempts', maxAttempts)),
    );
    await _db.transaction((txn) async {
      for (final r in failedRecs) {
        await _store.record(r.key).delete(txn);
      }
    });
    await _refreshCounts();
  }

  /// Reintentar las parkeadas: contador de intentos a cero.
  Future<void> retryFailed() async {
    final failedRecs = await _store.find(
      _db,
      finder:
          Finder(filter: Filter.greaterThanOrEquals('attempts', maxAttempts)),
    );
    await _db.transaction((txn) async {
      for (final r in failedRecs) {
        await _store.record(r.key).put(txn, {...r.value, 'attempts': 0});
      }
    });
    await _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    pendingCount.value = await _store.count(
        _db, filter: Filter.lessThan('attempts', maxAttempts));
    failedCount.value = await _store.count(_db,
        filter: Filter.greaterThanOrEquals('attempts', maxAttempts));
  }
}
