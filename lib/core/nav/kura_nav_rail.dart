import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens.dart';
import 'nav_destination.dart';

/// Riel de navegación único (canvas "Navegación KuraTracker", dirección B). DOS
/// estados —abierto (≥1200 px, 240 px) y colapsado (<1200 px, 72 px)— pintados de la
/// MISMA declaración ([NavDestination]). Un solo nivel de anidación. Navega con
/// `context.go`; la pantalla activa se deriva de [currentRoute], nunca de un entero.
/// Todo color desde [BrandTokens] (se usa igual en morado, azul y rosa); el alias
/// legado de color (siempre morado) queda prohibido en el chrome.
class KuraNavRail extends StatelessWidget {
  final List<NavDestination> destinations;
  final String currentRoute;
  final bool collapsed;
  final String brandName;
  final String? userName;
  final String? centerName;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onSearch;

  const KuraNavRail({
    super.key,
    required this.destinations,
    required this.currentRoute,
    required this.collapsed,
    this.brandName = 'KuraTracker',
    this.userName,
    this.centerName,
    this.onToggleCollapse,
    this.onSearch,
  });

  void _go(BuildContext context, String route) => context.go(route);

  @override
  Widget build(BuildContext context) {
    // Un solo nivel y rutas válidas: se hace cumplir aquí (rompe en pruebas).
    assertSingleLevel(destinations);
    assertRoutesValid(destinations);
    final t = BrandTokens.of(context);
    final visible = destinations.where((d) => d.isVisible).toList();
    return collapsed
        ? _collapsed(context, t, visible)
        : _open(context, t, visible);
  }

  // ----------------------------------------------------------------- Abierto
  Widget _open(BuildContext context, BrandTokens t, List<NavDestination> v) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, t),
          _searchOpen(t),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              children: [for (final d in v) _destOpen(context, t, d)],
            ),
          ),
          _footer(t),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, BrandTokens t) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: t.brandPrimary,
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.healing, size: 17, color: t.onBrand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(brandName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary)),
            ),
            IconButton(
              tooltip: 'Colapsar',
              onPressed: onToggleCollapse,
              icon: Icon(Icons.chevron_left, size: 20, color: t.textSecondary),
            ),
          ],
        ),
      );

  Widget _searchOpen(BrandTokens t) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: InkWell(
          onTap: onSearch,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: t.background,
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 16, color: t.textDisabled),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Buscar o ir a…',
                      style: TextStyle(fontSize: 12, color: t.textDisabled)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                      color: t.chipBg, borderRadius: BorderRadius.circular(5)),
                  child: Text('⌘K',
                      style: TextStyle(fontSize: 11, color: t.textSecondary)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _destOpen(BuildContext context, BrandTokens t, NavDestination d) {
    final active = navRouteIsActive(d, currentRoute);
    final selfActive = d.route == currentRoute;
    final row = InkWell(
      onTap: () => _go(context, d.route),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: active ? t.chipBg : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(d.icon,
                size: 18, color: active ? t.brandPrimary : t.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(d.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? t.brandPrimary : t.textPrimary)),
            ),
            if (d.hasChildren)
              Icon(active ? Icons.expand_more : Icons.chevron_right,
                  size: 16, color: t.textSecondary),
          ],
        ),
      ),
    );
    final keyedRow =
        selfActive ? KeyedSubtree(key: _activeKey(d.route), child: row) : row;

    if (!(d.hasChildren && active)) return keyedRow;

    // Con hijos y activo: expande sus hijos EN EL LUGAR (§2.1).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        keyedRow,
        Container(
          margin: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
          padding: const EdgeInsets.only(left: 18),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: t.chipBg, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in d.children.where((c) => c.isVisible))
                _childOpen(context, t, c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _childOpen(BuildContext context, BrandTokens t, NavDestination c) {
    final active = c.route == currentRoute;
    final w = InkWell(
      onTap: () => _go(context, c.route),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? t.background : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(c.label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                color: active ? t.textPrimary : t.textSecondary)),
      ),
    );
    return active ? KeyedSubtree(key: _activeKey(c.route), child: w) : w;
  }

  Widget _footer(BrandTokens t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: t.chipBg, shape: BoxShape.circle),
              child: Text(
                (userName ?? '?').characters.first.toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.brandPrimary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(userName ?? '—',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary)),
                  if (centerName != null)
                    Text(centerName!,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 11, color: t.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      );

  // --------------------------------------------------------------- Colapsado
  Widget _collapsed(BuildContext context, BrandTokens t, List<NavDestination> v) {
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          IconButton(
            tooltip: 'Buscar',
            onPressed: onSearch,
            icon: Icon(Icons.search, size: 19, color: t.textSecondary),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [for (final d in v) _destCollapsed(context, t, d)],
            ),
          ),
          IconButton(
            tooltip: 'Expandir',
            onPressed: onToggleCollapse,
            icon: Icon(Icons.chevron_right, size: 20, color: t.textSecondary),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _destCollapsed(BuildContext context, BrandTokens t, NavDestination d) {
    final active = navRouteIsActive(d, currentRoute);
    final selfActive = d.route == currentRoute;
    final box = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 5),
      child: InkWell(
        key: ValueKey('nav-icon:${d.route}'),
        onTap: () => _go(context, d.route),
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            if (active)
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                    color: t.brandPrimary,
                    borderRadius: BorderRadius.circular(3)),
              ),
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? t.chipBg : null,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(d.icon,
                  size: 19, color: active ? t.brandPrimary : t.textSecondary),
            ),
          ],
        ),
      ),
    );
    return selfActive
        ? KeyedSubtree(key: _activeKey(d.route), child: box)
        : box;
  }

  static Key _activeKey(String route) => ValueKey('nav-active:$route');
}

/// Menú del ENCABEZADO del contenido en estado colapsado (§2.2): dice la sección
/// activa como `Administración › Configuración ▾` y despliega las hermanas (los
/// hijos del destino). En colapsado los hijos NO están en el riel, así que ESTE menú
/// es lo que los mantiene alcanzables. Quitarlo deja los hijos inalcanzables.
class KuraSectionMenu extends StatelessWidget {
  final NavDestination section;
  final String currentRoute;
  const KuraSectionMenu({
    super.key,
    required this.section,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final children = section.children.where((c) => c.isVisible).toList();
    final active = children.where((c) => c.route == currentRoute);
    final activeLabel = active.isEmpty ? null : active.first.label;

    return PopupMenuButton<String>(
      tooltip: 'Cambiar de sección',
      onSelected: (route) => context.go(route),
      itemBuilder: (_) => [
        for (final c in children)
          PopupMenuItem<String>(value: c.route, child: Text(c.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: t.background,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              activeLabel == null
                  ? section.label
                  : '${section.label} › $activeLabel',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary),
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_more, size: 16, color: t.textSecondary),
          ],
        ),
      ),
    );
  }
}
