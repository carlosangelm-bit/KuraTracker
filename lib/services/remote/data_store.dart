/// Interfaz comun para el almacen de datos, implementada por [LocalStore]
/// (demo offline-first, SharedPreferences) y por [SupabaseDataStore]
/// (produccion, Postgrest + RLS en vivo).
///
/// DECISION DE ARQUITECTURA (paso 1 del roadmap): para minimizar el riesgo
/// de romper la UI en las 9+ pantallas que consumen [DataRepository], la
/// migracion a Supabase real NO cambia la forma de la API publica de
/// DataRepository. En su lugar, se introduce esta interfaz con:
///   - Lecturas SINCRONAS (`getAll`) que leen de una cache en memoria.
///   - Escrituras ASINCRONAS de grano fino (insertRow/updateRow/deleteRow/
///     upsertRow) que, en el caso de Supabase, hacen la llamada real a
///     Postgrest y luego actualizan la cache local para que las lecturas
///     sincronas subsecuentes reflejen el cambio sin round-trip adicional.
/// El nombre de cada "collection" coincide 1:1 con el nombre de tabla SQL
/// (ver Collections en local_store.dart), por lo que dobla como nombre de
/// tabla Postgrest sin necesidad de mapeo adicional.
abstract class DataStore {
  /// Lectura sincrona desde la cache en memoria (poblada por hydrate() en
  /// el caso remoto, o leida directamente de SharedPreferences en local).
  List<Map<String, dynamic>> getAll(String collection);

  /// Inserta una fila nueva. El mapa `data` debe incluir 'id' si el
  /// llamador ya genero uno (UUID client-side); si no lo trae, la
  /// implementacion remota deja que Postgres/Postgrest lo genere
  /// (default gen_random_uuid()) y lo refleja en la cache tras el insert.
  Future<Map<String, dynamic>> insertRow(String collection, Map<String, dynamic> data);

  /// Actualiza una fila existente por id con un patch parcial.
  Future<Map<String, dynamic>> updateRow(
      String collection, String id, Map<String, dynamic> patch);

  /// Elimina una fila por id.
  Future<void> deleteRow(String collection, String id);

  /// Insert-or-update (por id). Usado cuando el llamador no sabe si la
  /// fila ya existe.
  Future<Map<String, dynamic>> upsertRow(String collection, Map<String, dynamic> data);

  /// Re-lee una coleccion completa desde el origen de datos (para
  /// refrescar la cache tras mutaciones en tablas relacionadas).
  Future<void> refreshCollection(String collection);

  /// Hidrata la cache en memoria con TODAS las colecciones visibles para el
  /// usuario actual (segun RLS, en el caso remoto). Se llama una vez tras el
  /// login (o al arrancar, en el caso local). En [LocalStoreDataStore] es un
  /// no-op (SharedPreferences ya actua como "cache" persistente).
  Future<void> hydrate();
}
