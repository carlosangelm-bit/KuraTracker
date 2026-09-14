import 'package:flutter/widgets.dart';

/// UNA sola declaración por destino (etiqueta, icono, ruta, hijos, condición de
/// visibilidad). De aquí se pintan los DOS estados del riel (abierto y colapsado) y
/// se derivan las rutas — no hay una segunda lista que sincronizar a mano (§3).
///
/// Un solo nivel: un destino puede tener hijos, pero un hijo NO. Los nietos se
/// resuelven en el contenido, no en el riel (§2.1). [assertSingleLevel] lo hace
/// cumplir en tiempo de prueba.
class NavDestination {
  final String label;
  final IconData icon;
  final String route;
  final List<NavDestination> children;

  /// Condición de visibilidad (módulo contratado, rol, etc.). null = siempre visible.
  final bool Function()? visibleWhen;

  const NavDestination({
    required this.label,
    required this.icon,
    required this.route,
    this.children = const [],
    this.visibleWhen,
  });

  bool get isVisible => visibleWhen?.call() ?? true;
  bool get hasChildren => children.isNotEmpty;
}

/// Un destino está activo si la URL actual es su ruta, o (teniendo hijos) cuelga de
/// ella. Un hijo está activo cuando la URL es exactamente su ruta.
bool navRouteIsActive(NavDestination d, String currentRoute) {
  if (currentRoute == d.route) return true;
  for (final c in d.children) {
    if (c.route == currentRoute) return true;
  }
  return d.hasChildren && currentRoute.startsWith('${d.route}/');
}

/// El riel es de UN SOLO NIVEL: destino → hijos, sin nietos. Lanza con un mensaje
/// que nombra al culpable si alguna declaración trae un tercer nivel.
void assertSingleLevel(List<NavDestination> destinations) {
  for (final d in destinations) {
    for (final c in d.children) {
      if (c.children.isNotEmpty) {
        throw StateError(
          'Navegación de un solo nivel: "${d.label} › ${c.label}" declara '
          'nietos (${c.children.map((g) => g.label).join(', ')}). '
          'Un tercer nivel se resuelve en el contenido, no en el riel.',
        );
      }
    }
  }
}

/// Rutas no vacías y únicas en toda la declaración (destinos + hijos). Una entrada
/// sin ruta válida (vacía o repetida) rompe esto.
void assertRoutesValid(List<NavDestination> destinations) {
  final seen = <String>{};
  void check(String label, String route) {
    if (route.trim().isEmpty) {
      throw StateError('El destino "$label" no tiene ruta.');
    }
    if (!seen.add(route)) {
      throw StateError('Ruta repetida en la navegación: "$route" ("$label").');
    }
  }

  for (final d in destinations) {
    check(d.label, d.route);
    for (final c in d.children) {
      check(c.label, c.route);
    }
  }
}

/// Destinos + hijos visibles, aplanados con su ruta — para la prueba de cobertura y
/// para el menú del encabezado en colapsado.
Iterable<({String label, String route})> navFlattenVisible(
    List<NavDestination> destinations) sync* {
  for (final d in destinations) {
    if (!d.isVisible) continue;
    yield (label: d.label, route: d.route);
    for (final c in d.children) {
      if (c.isVisible) yield (label: c.label, route: c.route);
    }
  }
}
