/// Decisión de redirección por AUTENTICACIÓN y ROL del router (la parte que no
/// depende del repositorio). Vive aparte, como función pura, para probarse contra la
/// MISMA lógica que usa el router real (no una réplica del patrón de rutas).
///
/// Devuelve la ruta a la que redirigir, o null para "continuá" (enfermería /
/// solo-lectura / gating por módulo, que dependen del repo y se resuelven en el
/// closure del router).
String? resolveNavRedirect({
  required bool loggedIn,
  required bool isDemoMode,
  required bool goingToLogin,
  required bool goingToDemo,
  required String matchedLocation,
  required String uriString, // state.uri.toString() — para capturar ?from en frío
  required String? fromParam, // state.uri.queryParameters['from']
  required bool isMaster,
  required bool isCaregiver,
  required bool isAdmin,
}) {
  // Enlace profundo en frío (sin sesión): guarda el destino pretendido para
  // restaurarlo al resolver la sesión. No se guardan destinos triviales ni de auth.
  if (!loggedIn && !goingToLogin && !goingToDemo) {
    if (isDemoMode) return '/demo';
    final from = uriString;
    final keep = from != '/' &&
        !from.startsWith('/login') &&
        !from.startsWith('/demo');
    return keep ? '/login?from=${Uri.encodeComponent(from)}' : '/login';
  }

  // Tras autenticarse estando en /login o /demo. El ?from= (enlace profundo en frío)
  // gana ANTES que los retornos por rol: un master/cuidador que entró a una ruta
  // profunda NO debe perderla. Si el destino no le corresponde a su rol, la pasada
  // siguiente del redirect (abajo) lo reajusta.
  if (loggedIn && (goingToLogin || goingToDemo)) {
    final from = fromParam;
    if (from != null &&
        from.isNotEmpty &&
        !from.startsWith('/login') &&
        !from.startsWith('/demo')) {
      return from;
    }
    if (isMaster) return '/platform';
    if (isCaregiver) return '/caregiver';
    return '/';
  }

  final location = matchedLocation;
  if (loggedIn && isMaster) {
    // El master cae en ruta clínica (tecleada/bookmark): a su área real.
    final isClinicalRoute = location == '/' ||
        location.startsWith('/patients') ||
        location == '/reports';
    if (isClinicalRoute) return '/platform';
  } else if (loggedIn && isCaregiver) {
    if (!location.startsWith('/caregiver')) return '/caregiver';
  } else if (loggedIn && location.startsWith('/caregiver')) {
    return '/';
  } else if (loggedIn && location.startsWith('/platform')) {
    // Un no-master que teclee /platform no tiene nada ahí.
    return '/';
  }

  // Compra de insumos y /admin: SOLO admin del centro (y master).
  final canPurchase = isAdmin || isMaster;
  if (loggedIn && !canPurchase) {
    const purchaseRoutes = {
      '/insumos/tienda',
      '/insumos/inventario',
      '/insumos/reabasto',
      '/insumos/mapeo',
    };
    if (purchaseRoutes.contains(location)) return '/insumos';
  }
  if (loggedIn && !canPurchase && location.startsWith('/admin')) {
    return '/';
  }

  return null;
}
