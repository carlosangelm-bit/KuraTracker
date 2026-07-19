import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/session_provider.dart';
import '../theme/kura_theme.dart';
import '../../models/app_user.dart';

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
      appBar: isWide
          ? null
          : AppBar(
              title: _brandTitle(),
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
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelect,
              destinations: destinationsBottom,
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
