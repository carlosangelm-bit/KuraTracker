import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens.dart';
import '../providers/session_provider.dart';
import '../theme/kura_theme.dart';
import '../widgets/kura_glass_card.dart';
import '../../models/app_user.dart';

/// Alto del contenido de la barra de navegacion flotante. Las pantallas
/// scrolleables del shell suman esto (mas el inset inferior del sistema) a su
/// padding inferior para que el ultimo elemento no quede tapado por la barra.
/// Con `extendBody: true`, el Scaffold ya expone este alto en
/// `MediaQuery.of(context).padding.bottom` del body.
const double kFloatingNavBarHeight = 64;

/// Shell de navegacion principal: NavigationRail en pantallas anchas,
/// BottomNavigationBar en moviles. Los items disponibles dependen del rol
/// (admin ve gestion de personal/sitios; clinico ve solo lo operativo).
class AppShell extends ConsumerWidget {
  final Widget child;
  final String currentPath;

  const AppShell({super.key, required this.child, required this.currentPath});

  List<_NavItem> _itemsFor(AppUser? user) {
    // El master (administrador de plataforma) es exclusivamente
    // estructural (organizations/sites/staff/note_option_catalog, ver
    // 0012_master_role.sql): no tiene pacientes/reportes propios, asi
    // que se le oculta esa navegacion clinica por completo (mostrarla
    // solo lo llevaria a pantallas vacias sin ningun proposito) y en su
    // lugar ve unicamente su area de Plataforma.
    if (user?.role == AppRole.master) {
      return const [
        _NavItem('/platform', Icons.hub_outlined, Icons.hub, 'Plataforma'),
        _NavItem('/import-export', Icons.sync_alt_outlined, Icons.sync_alt, 'eKare'),
      ];
    }

    final items = <_NavItem>[
      const _NavItem('/', Icons.dashboard_outlined, Icons.dashboard, 'Inicio'),
      const _NavItem('/patients', Icons.people_outline, Icons.people, 'Pacientes'),
      const _NavItem('/agenda', Icons.event_outlined, Icons.event, 'Agenda'),
      const _NavItem('/reports', Icons.description_outlined, Icons.description, 'Reportes'),
    ];
    if (user?.role == AppRole.admin) {
      items.add(const _NavItem(
          '/admin', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, 'Administración'));
    }
    items.add(const _NavItem('/import-export', Icons.sync_alt_outlined, Icons.sync_alt, 'eKare'));
    return items;
  }

  int _indexFor(String path, List<_NavItem> items) {
    for (var i = 0; i < items.length; i++) {
      if (path == items[i].path || (items[i].path != '/' && path.startsWith(items[i].path))) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final items = _itemsFor(session.user);
    final selectedIndex = _indexFor(currentPath, items);
    final isWide = MediaQuery.of(context).size.width >= 900;
    final t = BrandTokens.of(context);

    final destinationsRail = items
        .map((i) => NavigationRailDestination(
              icon: Icon(i.icon),
              selectedIcon: Icon(i.selectedIcon),
              label: Text(i.label),
            ))
        .toList();

    final destinationsBottom = items
        .map((i) => NavigationDestination(
              icon: Icon(i.icon),
              selectedIcon: Icon(i.selectedIcon),
              label: i.label,
            ))
        .toList();

    void onSelect(int index) => context.go(items[index].path);

    return Scaffold(
      // El contenido pasa por DEBAJO de la barra flotante (para que el vidrio
      // lo refracte). Las pantallas scrolleables compensan con padding inferior
      // (ver kFloatingNavBarHeight / MediaQuery.padding.bottom).
      extendBody: true,
      // En movil se quita el titulo de marca ("KuraTracker") para ganar
      // espacio vertical: casi todas las pantallas ya tienen su propio AppBar
      // con su titulo, y el dashboard su propio encabezado. Queda una franja
      // delgada y transparente solo con el avatar (para conservar el acceso a
      // cerrar sesion en todas las pantallas).
      appBar: isWide
          ? null
          : AppBar(
              toolbarHeight: 44,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              actions: [_userMenu(context, ref, session)],
            ),
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelect,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: _brandTitle(compact: true),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _userMenu(context, ref, session, vertical: true),
                      ),
                    ),
                  ),
                  destinations: destinationsRail,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            )
          : child,
      // Barra de navegacion FLOTANTE estilo "liquid glass": no pegada a los
      // bordes (margen + esquinas casi pildora), acabado de vidrio consistente
      // con KuraGlassCard y sombra en capas para verse despegada del fondo.
      bottomNavigationBar: isWide
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: KuraGlassCard(
                  borderRadius: 30,
                  padding: EdgeInsets.zero,
                  child: NavigationBarTheme(
                    data: NavigationBarThemeData(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      surfaceTintColor: Colors.transparent,
                      // "Pill" del acento Kura detras del item activo
                      // (navegacion = accion, uso legitimo del acento).
                      indicatorColor: t.brandPrimary.withOpacity(0.16),
                      labelTextStyle: WidgetStateProperty.resolveWith((states) {
                        final selected = states.contains(WidgetState.selected);
                        return TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? t.brandPrimary : t.textSecondary,
                        );
                      }),
                      iconTheme: WidgetStateProperty.resolveWith((states) {
                        final selected = states.contains(WidgetState.selected);
                        return IconThemeData(
                          size: 24,
                          color: selected ? t.brandPrimary : t.textSecondary,
                        );
                      }),
                    ),
                    child: NavigationBar(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onSelect,
                      destinations: destinationsBottom,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      height: kFloatingNavBarHeight,
                      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _brandTitle({bool compact = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: KuraColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.healing, color: Colors.white, size: 20),
        ),
        if (!compact) ...[
          const SizedBox(width: 8),
          const Text('KuraTracker',
              style: TextStyle(fontWeight: FontWeight.w800, color: KuraColors.darkText)),
        ],
      ],
    );
  }

  Widget _userMenu(BuildContext context, WidgetRef ref, SessionState session,
      {bool vertical = false}) {
    final user = session.user;
    if (user == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: user.fullName,
      onSelected: (value) {
        if (value == 'logout') {
          ref.read(sessionProvider.notifier).logout();
          context.go('/login');
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        PopupMenuItem(enabled: false, child: Text(user.role.label)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
      ],
      child: CircleAvatar(
        backgroundColor: KuraColors.primary.withOpacity(0.15),
        child: Text(
          user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
          style: const TextStyle(color: KuraColors.primary, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _NavItem {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.path, this.icon, this.selectedIcon, this.label);
}
