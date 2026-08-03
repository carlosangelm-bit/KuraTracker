import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estado de una operación en la cola offline.
///  - `pending`: por sincronizar (o reintentando con backoff).
///  - `failed`: rechazada de forma no-transitoria (RLS/validación) tras agotar
///    los reintentos; no se drena sola — requiere atención del usuario.
///  - `conflict`: la fila cambió en el servidor desde la edición offline
///    (concurrencia); no se sobreescribe — requiere decisión del usuario.
class OutboxStatus {
  static const pending = 'pending';
  static const failed = 'failed';
  static const conflict = 'conflict';
}

/// Una escritura pendiente de sincronizar con Supabase (encolada mientras no
/// había red). Se aplica al reconectar, en orden de captura.
class OutboxOp {
  final String opId;
  final String collection;
  final String type; // insert | update | delete | upsert
  final String? rowId;
  final Map<String, dynamic> payload; // insert/upsert: fila; update: patch
  final String createdAt;
  final int attempts;
  final String? lastError;
  final String status;
  // Para UPDATE: `updated_at` de la fila al momento de editar offline. Permite
  // detectar conflictos (compare-and-set) al sincronizar.
  final String? baseUpdatedAt;

  const OutboxOp({
    required this.opId,
    required this.collection,
    required this.type,
    required this.rowId,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.status = OutboxStatus.pending,
    this.baseUpdatedAt,
  });

  OutboxOp copyWith({int? attempts, String? lastError, String? status}) =>
      OutboxOp(
        opId: opId,
        collection: collection,
        type: type,
        rowId: rowId,
        payload: payload,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
        status: status ?? this.status,
        baseUpdatedAt: baseUpdatedAt,
      );

  bool get isPending => status == OutboxStatus.pending;

  Map<String, dynamic> toJson() => {
        'op_id': opId,
        'collection': collection,
        'type': type,
        'row_id': rowId,
        'payload': payload,
        'created_at': createdAt,
        'attempts': attempts,
        'last_error': lastError,
        'status': status,
        'base_updated_at': baseUpdatedAt,
      };

  factory OutboxOp.fromJson(Map<String, dynamic> j) => OutboxOp(
        opId: j['op_id'] as String,
        collection: j['collection'] as String,
        type: j['type'] as String,
        rowId: j['row_id'] as String?,
        payload: (j['payload'] as Map).cast<String, dynamic>(),
        createdAt: j['created_at'] as String,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        lastError: j['last_error'] as String?,
        status: j['status'] as String? ?? OutboxStatus.pending,
        baseUpdatedAt: j['base_updated_at'] as String?,
      );
}

/// Cola persistente de escrituras offline (Fase 1) con robustez (Fase 4):
/// reintentos, estado por operación (pendiente/fallida/conflicto) y contadores
/// separados para la UI. Persistida en `SharedPreferences` (localStorage Web).
class OfflineOutbox {
  static const _key = 'offline_outbox_v1';

  /// Reintentos ante rechazo no-transitorio antes de "parkear" (Fase 4).
  static const maxAttempts = 5;

  final SharedPreferences _prefs;
  List<OutboxOp> _ops;

  /// Operaciones aún por sincronizar (estado pending).
  final ValueNotifier<int> pendingCount;

  /// Operaciones que requieren atención (failed/conflict).
  final ValueNotifier<int> failedCount;

  OfflineOutbox._(this._prefs, this._ops)
      : pendingCount =
            ValueNotifier<int>(_ops.where((o) => o.isPending).length),
        failedCount =
            ValueNotifier<int>(_ops.where((o) => !o.isPending).length);

  static Future<OfflineOutbox> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final ops = <OutboxOp>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in (jsonDecode(raw) as List)) {
          ops.add(OutboxOp.fromJson((e as Map).cast<String, dynamic>()));
        }
      } catch (e) {
        debugPrint('OfflineOutbox: cola corrupta, se descarta: $e');
      }
    }
    return OfflineOutbox._(prefs, ops);
  }

  bool get isEmpty => _ops.isEmpty;
  int get length => _ops.length;

  List<OutboxOp> all() => List.unmodifiable(_ops);

  /// Solo las que se deben intentar drenar (pendientes).
  List<OutboxOp> pending() =>
      _ops.where((o) => o.isPending).toList(growable: false);

  /// Las que requieren atención del usuario (failed/conflict).
  List<OutboxOp> failed() =>
      _ops.where((o) => !o.isPending).toList(growable: false);

  Future<void> enqueue(OutboxOp op) async {
    _ops.add(op);
    await _persist();
  }

  Future<void> remove(String opId) async {
    _ops.removeWhere((o) => o.opId == opId);
    await _persist();
  }

  /// Registra un fallo. Si es conflicto, o se agotaron los reintentos, la
  /// "parkea" (failed/conflict); si no, incrementa intentos y sigue pending.
  Future<void> markFailed(String opId, String error,
      {bool conflict = false}) async {
    final i = _ops.indexWhere((o) => o.opId == opId);
    if (i < 0) return;
    final attempts = _ops[i].attempts + 1;
    final park = conflict || attempts >= maxAttempts;
    _ops[i] = _ops[i].copyWith(
      attempts: attempts,
      lastError: error,
      status: park
          ? (conflict ? OutboxStatus.conflict : OutboxStatus.failed)
          : OutboxStatus.pending,
    );
    await _persist();
  }

  /// Descarta (borra) las parkeadas (failed/conflict). Las pendientes se
  /// conservan.
  Future<void> discardFailed() async {
    _ops.removeWhere((o) => !o.isPending);
    await _persist();
  }

  /// Reintentar las parkeadas: vuelven a pending con el contador a cero.
  Future<void> retryFailed() async {
    for (var i = 0; i < _ops.length; i++) {
      if (!_ops[i].isPending) {
        _ops[i] = _ops[i].copyWith(attempts: 0, status: OutboxStatus.pending);
      }
    }
    await _persist();
  }

  Future<void> clear() async {
    _ops = [];
    await _persist();
  }

  Future<void> _persist() async {
    await _prefs.setString(
        _key, jsonEncode(_ops.map((o) => o.toJson()).toList()));
    pendingCount.value = _ops.where((o) => o.isPending).length;
    failedCount.value = _ops.where((o) => !o.isPending).length;
  }
}
