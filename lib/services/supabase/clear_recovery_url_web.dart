import 'package:web/web.dart' as web;

/// Quita los parámetros de auth (p. ej. `?code=`) de la barra de direcciones tras canjear el
/// enlace, SIN recargar. `getSessionFromUrl` NO limpia la URL (supabase lo hace aparte, con
/// clearAuthUrlParameters(), que no está exportada). Si el `?code=` se queda, recargar
/// /reset-password reintenta un código YA GASTADO → error de vencido con el usuario a media
/// captura de su contraseña. Mismo remedio que usa el SDK: replaceState al path limpio.
void clearRecoveryUrl() {
  final loc = web.window.location;
  web.window.history.replaceState(null, '', loc.pathname);
}
