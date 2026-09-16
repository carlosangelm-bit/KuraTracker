import 'package:flutter/foundation.dart' show kIsWeb;
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

  /// Se prende si la URL inicial trae un enlace de recuperación que emitió passwordRecovery. El
  /// router lo CONSUME una vez para sembrar passwordRecoveryProvider. Existe por la CARRERA (§prod):
  /// con detectSessionInUri por defecto, ese evento se emitía DENTRO de Supabase.initialize —antes
  /// de que el listener del router existiera— y se perdía (broadcast sin replay). Con sesión previa
  /// el usuario terminaba en la app (o en la cuenta equivocada) en vez de en /reset-password.
  static bool passwordRecoveryFromUrl = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    // detectSessionInUri:false → NO se procesa la URL DENTRO de initialize; se hace a mano abajo,
    // ya con el listener puesto, para no perder el evento passwordRecovery (la carrera).
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      debug: false,
      authOptions:
          const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    // Listener ANTES de tocar la URL: así el passwordRecovery de la URL inicial SÍ se captura.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        passwordRecoveryFromUrl = true;
      }
    });
    // Procesa la URL inicial a mano (lo que detectSessionInUri hacía dentro de initialize).
    // CONDICIÓN 1 (Carlos): ENVUELTO. Una URL normal (sin credencial de auth) hace que
    // getSessionFromUrl LANCE; si falla —URL no-auth, o token vencido/usado— la app arranca IGUAL
    // y el usuario ve el login. Sin esta guarda, el fallo no sería "no sirve la recuperación", sería
    // PANTALLA EN BLANCO PARA TODOS — el único modo de falla peor que el bug que arreglamos.
    if (kIsWeb && _looksLikeAuthCallback(Uri.base)) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(Uri.base);
      } catch (_) {
        // token vencido/usado, o no era auth: el login lee el error del query string (login-mute)
        // y ofrece pedir otro. NUNCA se tumba el arranque.
      }
    }
    _initialized = true;
  }

  /// ¿La URL parece un callback de auth con credencial a canjear? Solo entonces se llama
  /// getSessionFromUrl (evita lanzar en cada arranque normal). El caso de solo-error lo lee el
  /// login desde el query string; aquí no se toca.
  static bool _looksLikeAuthCallback(Uri uri) {
    final q = <String, String>{...uri.queryParameters};
    if (uri.fragment.isNotEmpty) {
      try {
        q.addAll(Uri.splitQueryString(uri.fragment));
      } catch (_) {}
    }
    return q.containsKey('code') ||
        q.containsKey('access_token') ||
        q.containsKey('token_hash');
  }

  /// Cliente global de Supabase. Solo valido despues de [initialize].
  static SupabaseClient get client => Supabase.instance.client;
}
