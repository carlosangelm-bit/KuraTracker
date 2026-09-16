// Limpia los parámetros de auth de la barra de direcciones del navegador tras canjear el enlace
// de recuperación (§prod, corrección 2 de Carlos). Web usa la History API; fuera de web es no-op.
// Import condicional: la implementación web solo se compila en web.
export 'clear_recovery_url_stub.dart'
    if (dart.library.js_interop) 'clear_recovery_url_web.dart';
