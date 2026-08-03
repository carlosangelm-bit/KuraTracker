import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Una escritura pendiente de sincronizar con Supabase (encolada mientras no
/// había red). Se aplica al reconectar, en orden de captura.
class OutboxOp {
  final String opId; // id único de la operación (no de la fila)
  final String collection; // tabla
  final String type; // insert | update | delete | upsert
  final String? rowId; // id (cliente) de la fila afectada
  final Map<String, dynamic> payload; // insert/upsert: fila completa; update: patch
  final String createdAt; // ISO
  final int attempts;
  final String? lastError;

  const OutboxOp({
    required this.opId,
    required this.collection,
    required this.type,
    required this.rowId,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  OutboxOp copyWith({int? attempts, String? lastError}) => OutboxOp(
        opId: opId,
        collection: collection,
        type: type,
        rowId: rowId,
        payload: payload,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'op_id': opId,
        'collection': collection,
        'type': type,
        'row_id': rowId,
        'payload': payload,
        'created_at': createdAt,
        'attempts': attempts,
        'last_error': lastError,
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
      );
}

/// Cola persistente de escrituras offline (Fase 1 de offline-first). Se guarda
/// en `SharedPreferences` (localStorage en Web) — suficiente para operaciones
/// de texto (consulta/medición/nota); las fotos van en una fase posterior.
///
/// El acceso es serializado por un cerrojo simple para evitar carreras entre
/// encolar (durante la captura) y drenar (durante el sync).
class OfflineOutbox {
  static const _key = 'offline_outbox_v1';

  final SharedPreferences _prefs;
  List<OutboxOp> _ops;

  /// Número de operaciones pendientes (para el indicador de UI).
  final ValueNotifier<int> pendingCount;

  OfflineOutbox._(this._prefs, this._ops)
      : pendingCount = ValueNotifier<int>(_ops.length);

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

  /// Copia inmutable de las operaciones en orden.
  List<OutboxOp> all() => List.unmodifiable(_ops);

  Future<void> enqueue(OutboxOp op) async {
    _ops.add(op);
    await _persist();
  }

  Future<void> remove(String opId) async {
    _ops.removeWhere((o) => o.opId == opId);
    await _persist();
  }

  Future<void> markFailed(String opId, String error) async {
    final i = _ops.indexWhere((o) => o.opId == opId);
    if (i < 0) return;
    _ops[i] = _ops[i].copyWith(attempts: _ops[i].attempts + 1, lastError: error);
    await _persist();
  }

  Future<void> clear() async {
    _ops = [];
    await _persist();
  }

  Future<void> _persist() async {
    await _prefs.setString(_key, jsonEncode(_ops.map((o) => o.toJson()).toList()));
    pendingCount.value = _ops.length;
  }
}
