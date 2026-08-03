import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../local_db/local_store.dart' show Collections;
import '../offline/offline_outbox.dart';
import '../offline/read_cache_store.dart';
import 'data_store.dart';

/// Implementacion de [DataStore] respaldada por Supabase real (Postgrest +
/// Auth + RLS). Es la fuente de datos autoritativa en produccion.
///
/// ESTRATEGIA DE CACHE (ver documentacion en [DataStore]):
///   - `hydrate()` se llama una vez tras un login exitoso: hace un SELECT *
///     de cada tabla en [Collections.all]. Gracias a RLS, cada SELECT
///     devuelve SOLO las filas visibles para el usuario autenticado (todas
///     si es admin; solo las de sus pacientes asignados si es clinico). El
///     resultado se guarda en una cache en memoria (`_cache`).
///   - `getAll()` es sincrono y lee unicamente de esa cache — nunca hace
///     I/O. Esto preserva la API sincrona que 9+ pantallas ya usan via
///     [DataRepository] sin tener que reescribir esas pantallas a
///     FutureBuilder/StreamBuilder.
///   - Las escrituras (`insertRow`/`updateRow`/`deleteRow`/`upsertRow`)
///     hacen la llamada real a Postgrest (respetando RLS: si la policy
///     rechaza la operacion, Postgrest devuelve 401/403 y se relanza como
///     [PostgrestException]) y, si tiene exito, actualizan la cache local
///     con la fila resultante para que la siguiente lectura sincrona la
///     refleje sin esperar un round-trip adicional.
///   - `refreshCollection()` vuelve a traer una tabla completa desde el
///     servidor; se usa cuando una mutacion en una tabla puede afectar la
///     forma de otra tabla relacionada en la UI (p.ej. tras borrar una
///     asignacion, refrescar `patients` para que listAllPatients() ya no
///     incluya un paciente que el usuario perdio visibilidad).
class SupabaseDataStore implements DataStore {
  final SupabaseClient _client;
  final Map<String, List<Map<String, dynamic>>> _cache = {};
  bool _hydrated = false;

  /// Cola offline (Fase 1). Si es null, las escrituras fallan como antes; si
  /// está presente, una falla POR RED encola la operación y actualiza la caché
  /// de forma optimista (se sincroniza al reconectar via [syncOutbox]).
  final OfflineOutbox? outbox;
  static const _uuid = Uuid();

  /// Persistencia de la caché de lectura (Fase 3). Si está presente, la caché
  /// en memoria se respalda en IndexedDB y se restaura al arrancar, de modo que
  /// los expedientes se ven SIN señal (al recargar/abrir offline).
  final ReadCacheStore? readCache;

  SupabaseDataStore(this._client, {this.outbox, this.readCache});

  /// Precarga en la caché en memoria la caché persistida (Fase 3), para que las
  /// lecturas funcionen offline aun antes/aunque falle hydrate(). No pisa
  /// colecciones ya presentes (p.ej. escrituras optimistas previas).
  void primeCache(Map<String, List<Map<String, dynamic>>> persisted) {
    for (final e in persisted.entries) {
      _cache.putIfAbsent(e.key, () => e.value);
    }
  }

  void _persistCollection(String collection) {
    final rc = readCache;
    if (rc == null) return;
    unawaited(rc.saveCollection(collection, _cache[collection] ?? const []));
  }

  /// Cliente Supabase subyacente. Expuesto para suscripciones Realtime
  /// (canales de `postgres_changes`) que viven fuera de la caché de tablas.
  SupabaseClient get client => _client;

  @override
  List<Map<String, dynamic>> getAll(String collection) {
    return _cache[collection] ?? const [];
  }

  @override
  Future<void> hydrate() async {
    for (final collection in Collections.all) {
      await refreshCollection(collection);
    }
    _hydrated = true;
  }

  bool get isHydrated => _hydrated;

  /// Limpia toda la cache en memoria (usado en logout, para no dejar datos
  /// del usuario anterior visibles si otro usuario inicia sesion despues
  /// en la misma pestana/instancia de la app).
  void clearCache() {
    _cache.clear();
    _hydrated = false;
  }

  @override
  Future<void> refreshCollection(String collection) async {
    // Resiliencia: un error en UNA colección (p.ej. una tabla que aún no existe
    // porque falta aplicar una migración, o un fallo transitorio de red) NO debe
    // romper toda la hidratación (login / carga inicial). Se registra y se
    // continúa; la feature de esa colección queda vacía hasta la próxima
    // hidratación, pero el resto de la app sigue funcionando. Antes, sin este
    // try/catch, un desfase código↔esquema tumbaba el login por completo.
    try {
      final rows = await _client.from(collection).select();
      _cache[collection] = (rows as List).cast<Map<String, dynamic>>();
      _persistCollection(collection);
    } catch (e) {
      debugPrint('refreshCollection("$collection") falló, se omite: $e');
      _cache.putIfAbsent(collection, () => <Map<String, dynamic>>[]);
    }
  }

  @override
  Future<Map<String, dynamic>> insertRow(
      String collection, Map<String, dynamic> data) async {
    // No se envia 'id' si viene null/vacio: se deja que Postgres lo genere
    // (default gen_random_uuid()) y que triggers (p.ej. folios) corran.
    final payload = Map<String, dynamic>.from(data);
    if (payload['id'] == null || (payload['id'] as String).isEmpty) {
      payload.remove('id');
    }
    try {
      final inserted =
          await _client.from(collection).insert(payload).select().single();
      final row = Map<String, dynamic>.from(inserted);
      _upsertIntoCache(collection, row);
      return row;
    } catch (e) {
      final queued = await _queueWriteIfOffline(collection, 'insert', data, e);
      if (queued != null) return queued;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> updateRow(
      String collection, String id, Map<String, dynamic> patch) async {
    try {
      final updated = await _client
          .from(collection)
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      final row = Map<String, dynamic>.from(updated);
      _upsertIntoCache(collection, row);
      return row;
    } catch (e) {
      final withId = {...patch, 'id': id};
      final queued = await _queueWriteIfOffline(collection, 'update', withId, e);
      if (queued != null) return queued;
      rethrow;
    }
  }

  @override
  Future<void> deleteRow(String collection, String id) async {
    try {
      await _client.from(collection).delete().eq('id', id);
      _cache[collection]?.removeWhere((e) => e['id'] == id);
      _persistCollection(collection);
    } catch (e) {
      final queued =
          await _queueWriteIfOffline(collection, 'delete', {'id': id}, e);
      if (queued == null) rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> upsertRow(
      String collection, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['id'] == null || (payload['id'] as String).isEmpty) {
      payload.remove('id');
    }
    try {
      final upserted =
          await _client.from(collection).upsert(payload).select().single();
      final row = Map<String, dynamic>.from(upserted);
      _upsertIntoCache(collection, row);
      return row;
    } catch (e) {
      final queued = await _queueWriteIfOffline(collection, 'upsert', data, e);
      if (queued != null) return queued;
      rethrow;
    }
  }

  /// Una escritura falló: si la cola offline está activa y el error parece de
  /// RED (no un rechazo del servidor: RLS/validación → [PostgrestException]),
  /// la encola y actualiza la caché de forma optimista, devolviendo la fila
  /// resultante. Devuelve null si NO se debe encolar (el llamador relanza).
  Future<Map<String, dynamic>?> _queueWriteIfOffline(
    String collection,
    String type,
    Map<String, dynamic> data,
    Object error,
  ) async {
    if (outbox == null || !_looksLikeNetworkError(error)) return null;

    final row = Map<String, dynamic>.from(data);
    if (type != 'delete' &&
        (row['id'] == null || (row['id'] as String).isEmpty)) {
      row['id'] = _uuid.v4();
    }
    final rowId = row['id'] as String?;

    await outbox!.enqueue(OutboxOp(
      opId: _uuid.v4(),
      collection: collection,
      type: type,
      rowId: rowId,
      payload: row,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    ));

    if (type == 'delete') {
      _cache[collection]?.removeWhere((e) => e['id'] == rowId);
      _persistCollection(collection);
      return const {};
    }
    if (type == 'update') {
      // Optimista: fusiona el patch sobre la fila en caché (o crea una mínima).
      final list = _cache.putIfAbsent(collection, () => []);
      final idx = list.indexWhere((e) => e['id'] == rowId);
      final merged = idx >= 0 ? {...list[idx], ...row} : row;
      _upsertIntoCache(collection, merged);
      return merged;
    }
    _upsertIntoCache(collection, row);
    return row;
  }

  /// Heurística: un [PostgrestException]/[AuthException]/[FunctionException]
  /// significa que el servidor RESPONDIÓ (rechazo por RLS/validación) → NO se
  /// encola (es un error real). Cualquier otra cosa (fetch fallido, socket,
  /// timeout) se trata como falta de red → se encola.
  bool _looksLikeNetworkError(Object e) =>
      !(e is PostgrestException || e is AuthException || e is FunctionException);

  /// Drena la cola offline aplicando cada operación a Supabase, en orden. Se
  /// llama al reconectar y tras hidratar. Idempotente: los insert/upsert se
  /// re-aplican como UPSERT (por id de cliente), así una operación que ya se
  /// había aplicado (respuesta perdida) no duplica. Devuelve cuántas se
  /// aplicaron. Si vuelve a fallar la red, se detiene y reintenta luego.
  Future<int> syncOutbox() async {
    final box = outbox;
    if (box == null || box.isEmpty) return 0;
    var applied = 0;
    for (final op in box.all()) {
      try {
        switch (op.type) {
          case 'insert':
          case 'upsert':
            final payload = Map<String, dynamic>.from(op.payload);
            final refreshed =
                await _client.from(op.collection).upsert(payload).select().single();
            _upsertIntoCache(op.collection, Map<String, dynamic>.from(refreshed));
            break;
          case 'update':
            final patch = Map<String, dynamic>.from(op.payload)..remove('id');
            final updated = await _client
                .from(op.collection)
                .update(patch)
                .eq('id', op.rowId as Object)
                .select()
                .maybeSingle();
            if (updated != null) {
              _upsertIntoCache(
                  op.collection, Map<String, dynamic>.from(updated));
            }
            break;
          case 'delete':
            await _client
                .from(op.collection)
                .delete()
                .eq('id', op.rowId as Object);
            break;
        }
        await box.remove(op.opId);
        applied++;
      } on PostgrestException catch (e) {
        // 23505 = unique_violation → la fila ya existía (op ya aplicada): OK.
        if (e.code == '23505') {
          await box.remove(op.opId);
          applied++;
          continue;
        }
        // Rechazo real (RLS/validación): parkear para no bloquear la cola.
        await box.markFailed(op.opId, e.message);
        continue;
      } catch (e) {
        // Sigue sin red: detener y reintentar en el próximo ciclo.
        break;
      }
    }
    return applied;
  }

  /// Invoca una Edge Function de Supabase. El cliente adjunta automaticamente
  /// el JWT del usuario autenticado (la funcion aplica su propia autorizacion
  /// del lado servidor, con service role). Se usa para operaciones que NO
  /// pueden hacerse solo con la anon key + RLS, como crear un usuario con
  /// login (Auth admin.createUser requiere service role). Lanza
  /// [FunctionException] si la funcion responde >= 400 (el llamador puede leer
  /// e.details para el mensaje de error).
  Future<Map<String, dynamic>> invokeFunction(
      String name, Map<String, dynamic> body) async {
    final res = await _client.functions.invoke(name, body: body);
    final data = res.data;
    if (data is Map) return data.cast<String, dynamic>();
    return {'data': data};
  }

  /// Llama a una función RPC de Postgres (SECURITY DEFINER). Usado para
  /// operaciones que RLS no permite como UPDATE directo pero sí de forma
  /// acotada/validada dentro de la función (p.ej. set_scheduling_mode).
  Future<void> callRpc(String name, Map<String, dynamic> params) async {
    await _client.rpc(name, params: params);
  }

  /// Como [callRpc] pero devuelve el resultado (p.ej. filas de una función que
  /// retorna una tabla, como get_org_acuity_status).
  Future<dynamic> callRpcResult(String name, Map<String, dynamic> params) async {
    return await _client.rpc(name, params: params);
  }

  void _upsertIntoCache(String collection, Map<String, dynamic> row) {
    final list = _cache.putIfAbsent(collection, () => []);
    final idx = list.indexWhere((e) => e['id'] == row['id']);
    if (idx >= 0) {
      list[idx] = row;
    } else {
      list.add(row);
    }
    _persistCollection(collection);
  }
}
