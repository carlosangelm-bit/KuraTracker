import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local_db/local_store.dart' show Collections;
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

  SupabaseDataStore(this._client);

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
    final inserted = await _client
        .from(collection)
        .insert(payload)
        .select()
        .single();
    final row = Map<String, dynamic>.from(inserted);
    _upsertIntoCache(collection, row);
    return row;
  }

  @override
  Future<Map<String, dynamic>> updateRow(
      String collection, String id, Map<String, dynamic> patch) async {
    final updated = await _client
        .from(collection)
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    final row = Map<String, dynamic>.from(updated);
    _upsertIntoCache(collection, row);
    return row;
  }

  @override
  Future<void> deleteRow(String collection, String id) async {
    await _client.from(collection).delete().eq('id', id);
    _cache[collection]?.removeWhere((e) => e['id'] == id);
  }

  @override
  Future<Map<String, dynamic>> upsertRow(
      String collection, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['id'] == null || (payload['id'] as String).isEmpty) {
      payload.remove('id');
    }
    final upserted = await _client
        .from(collection)
        .upsert(payload)
        .select()
        .single();
    final row = Map<String, dynamic>.from(upserted);
    _upsertIntoCache(collection, row);
    return row;
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
  }
}
