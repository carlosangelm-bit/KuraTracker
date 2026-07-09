import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';

/// Inicializacion del cliente Supabase (Auth + Postgrest + Storage).
///
/// Se invoca una sola vez en `main()` cuando [AppConfig.isSupabaseConfigured]
/// es true (es decir, cuando la app se compilo con --dart-define=SUPABASE_URL=...
/// --dart-define=SUPABASE_ANON_KEY=...). En modo demo local (sin credenciales)
/// esta clase nunca se invoca y la app opera 100% con LocalStore.
///
/// IMPORTANTE (seguridad): solo se usa la anon/publishable key aqui. La
/// service_role/secret key NUNCA debe incluirse en el cliente Flutter — toda
/// operacion que requiera privilegios elevados se hace via RLS (politicas
/// por rol/asignacion) o, en el futuro, desde la Edge Function (paso 3 del
/// roadmap), que corre en el servidor con su propio contexto de autenticacion.
class SupabaseBootstrap {
  SupabaseBootstrap._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      debug: false,
    );
    _initialized = true;
  }

  /// Cliente global de Supabase. Solo valido despues de [initialize].
  static SupabaseClient get client => Supabase.instance.client;
}
