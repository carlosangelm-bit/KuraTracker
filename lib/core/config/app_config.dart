/// Configuracion de la app. Las credenciales de Supabase se inyectan via
/// --dart-define en tiempo de build (nunca hardcodeadas en el repo).
///
/// Mientras no se configuren credenciales reales, la app opera en modo
/// LOCAL-FIRST DEMO: toda la persistencia vive en SQLite local (sqflite /
/// sqflite_common_ffi_web) con datos de ejemplo precargados. Esto permite
/// una demo navegable completa sin depender de un proyecto Supabase activo.
/// El SyncService (lib/services/sync) sincroniza con Supabase automaticamente
/// en cuanto se detectan credenciales validas y conectividad.
class AppConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Limite de tamano por lote de evidencia fotografica (seccion 3/9).
  static const int maxPhotoBatchBytes = 17 * 1024 * 1024; // 17 MB

  static const String appName = 'KuraTracker';
  static const String brandName = 'Kura+ / CuraMas';
}
