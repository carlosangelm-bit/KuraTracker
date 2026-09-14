import 'package:flutter/material.dart';

import '../../models/module_key.dart';
import 'nav_destination.dart';

/// LA declaración de rutas de la app (§3): una sola lista de la que se pintan los dos
/// estados del riel y se derivan las rutas. Sustituye al doble riel + `_tab`/`switch`.
/// Cada módulo se ve solo si su interruptor/derecho lo habilita ([moduleEnabled]);
/// Administración se ve para el admin y anida sus secciones (un nivel).
///
/// Las rutas hijas de Administración las formaliza la etapa 3; aquí viven como la
/// única declaración, no se cablea ninguna pantalla todavía.
List<NavDestination> kuraNavDestinations({
  required bool Function(String moduleKey) moduleEnabled,
  required bool isAdmin,
  required bool isMaster,
}) {
  NavDestination mod(ModuleKey m, IconData icon) => NavDestination(
        label: m.label,
        icon: icon,
        route: m.route,
        visibleWhen: () => moduleEnabled(m.dbValue),
      );

  return [
    mod(ModuleKey.patients, Icons.people_outline),
    mod(ModuleKey.agenda, Icons.calendar_today_outlined),
    mod(ModuleKey.prevention, Icons.shield_outlined),
    mod(ModuleKey.reports, Icons.bar_chart_outlined),
    mod(ModuleKey.insumos, Icons.inventory_2_outlined),
    mod(ModuleKey.comercial, Icons.sell_outlined),
    mod(ModuleKey.vac, Icons.healing_outlined),
    mod(ModuleKey.ekare, Icons.file_upload_outlined),
    NavDestination(
      label: 'Administración',
      icon: Icons.settings_outlined,
      route: '/admin',
      visibleWhen: () => isAdmin,
      children: const [
        NavDestination(
            label: 'Configuración',
            icon: Icons.tune_outlined,
            route: '/admin/configuracion'),
        NavDestination(
            label: 'Usuarios',
            icon: Icons.group_outlined,
            route: '/admin/usuarios'),
        NavDestination(
            label: 'Sitios',
            icon: Icons.location_on_outlined,
            route: '/admin/sitios'),
        NavDestination(
            label: 'Catálogo',
            icon: Icons.list_alt_outlined,
            route: '/admin/catalogo'),
        NavDestination(
            label: 'Marca',
            icon: Icons.palette_outlined,
            route: '/admin/marca'),
        NavDestination(
            label: 'Licencias',
            icon: Icons.workspace_premium_outlined,
            route: '/admin/licencias'),
      ],
    ),
    // Plataforma: la consola del master. Nueve secciones, cada una con su ruta
    // propia (§5 etapa 2). Sustituye al riel doble + `_tab`/switch de /platform.
    NavDestination(
      label: 'Plataforma',
      icon: Icons.hub_outlined,
      route: '/platform',
      visibleWhen: () => isMaster,
      children: const [
        NavDestination(
            label: 'Centros',
            icon: Icons.business_outlined,
            route: '/platform/centros'),
        NavDestination(
            label: 'Usuarios',
            icon: Icons.people_outline,
            route: '/platform/usuarios'),
        NavDestination(
            label: 'Personal',
            icon: Icons.medical_services_outlined,
            route: '/platform/personal'),
        NavDestination(
            label: 'Sitios',
            icon: Icons.location_on_outlined,
            route: '/platform/sitios'),
        NavDestination(
            label: 'Catálogo',
            icon: Icons.list_alt_outlined,
            route: '/platform/catalogo'),
        NavDestination(
            label: 'Marca',
            icon: Icons.palette_outlined,
            route: '/platform/marca'),
        NavDestination(
            label: 'Módulos',
            icon: Icons.tune_outlined,
            route: '/platform/modulos'),
        NavDestination(
            label: 'Solicitudes',
            icon: Icons.request_page_outlined,
            route: '/platform/solicitudes'),
        NavDestination(
            label: 'Licencia',
            icon: Icons.workspace_premium_outlined,
            route: '/platform/licencia'),
      ],
    ),
  ];
}

/// Las secciones del master, listas para el riel de /platform: la declaración
/// filtrada a "Plataforma" (y sus nueve hijos). Fuente única — la misma
/// declaración de [kuraNavDestinations].
List<NavDestination> platformNavDestinations() => kuraNavDestinations(
      moduleEnabled: (_) => false,
      isAdmin: false,
      isMaster: true,
    ).where((d) => d.route == '/platform').toList();
