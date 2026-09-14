import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/core/router/nav_redirect.dart';

/// Simula el corte en frío: se teclea [typed] sin sesión (se captura ?from), luego
/// se resuelve la sesión y se ITERA la redirección hasta punto fijo — exactamente lo
/// que hace go_router. Usa la MISMA función que el router real (resolveNavRedirect),
/// no una réplica del patrón de rutas.
String coldEntry(String typed,
    {required bool isMaster, required bool isCaregiver, bool isAdmin = false}) {
  // Paso 1: sin sesión → captura del destino en ?from.
  var loc = resolveNavRedirect(
        loggedIn: false,
        isDemoMode: false,
        goingToLogin: typed == '/login',
        goingToDemo: typed == '/demo',
        matchedLocation: typed,
        uriString: typed,
        fromParam: null,
        isMaster: isMaster,
        isCaregiver: isCaregiver,
        isAdmin: isAdmin,
      ) ??
      typed;

  // Paso 2: con sesión, iterar hasta estable (como el redirect loop de go_router).
  for (var i = 0; i < 12; i++) {
    final uri = Uri.parse(loc);
    final r = resolveNavRedirect(
      loggedIn: true,
      isDemoMode: false,
      goingToLogin: uri.path == '/login',
      goingToDemo: uri.path == '/demo',
      matchedLocation: uri.path,
      uriString: loc,
      fromParam: uri.queryParameters['from'],
      isMaster: isMaster,
      isCaregiver: isCaregiver,
      isAdmin: isAdmin,
    );
    if (r == null || r == loc) return uri.path;
    loc = r;
  }
  return Uri.parse(loc).path;
}

void main() {
  test('1 · master en frío a /platform/licencia conserva el destino', () {
    expect(coldEntry('/platform/licencia', isMaster: true, isCaregiver: false),
        '/platform/licencia');
  });

  test('2 · master en frío a ruta clínica (/patients) termina en /platform', () {
    // El ?from se restaura y la pasada siguiente lo reajusta a /platform (como hoy).
    expect(coldEntry('/patients', isMaster: true, isCaregiver: false),
        '/platform');
  });

  test('3 · cuidador en frío a una subruta de /caregiver la conserva', () {
    expect(coldEntry('/caregiver/tareas', isMaster: false, isCaregiver: true),
        '/caregiver/tareas');
  });

  test('4 · las nueve secciones de /platform, en frío, llegan a la tecleada', () {
    const sections = [
      'centros', 'usuarios', 'personal', 'sitios', 'catalogo', 'marca',
      'modulos', 'solicitudes', 'licencia',
    ];
    for (final s in sections) {
      expect(
        coldEntry('/platform/$s', isMaster: true, isCaregiver: false),
        '/platform/$s',
        reason: s,
      );
    }
  });

  test('el ?from gana ANTES que el retorno por rol (la pieza que falló)', () {
    // Directo sobre la función: en /login con sesión de master y ?from profundo,
    // devuelve el from, no /platform.
    expect(
      resolveNavRedirect(
        loggedIn: true,
        isDemoMode: false,
        goingToLogin: true,
        goingToDemo: false,
        matchedLocation: '/login',
        uriString: '/login?from=%2Fplatform%2Flicencia',
        fromParam: '/platform/licencia',
        isMaster: true,
        isCaregiver: false,
        isAdmin: false,
      ),
      '/platform/licencia',
    );
  });
}
