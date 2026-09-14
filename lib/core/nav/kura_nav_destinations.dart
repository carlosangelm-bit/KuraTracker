import 'package:flutter/material.dart';

import '../../models/center_type.dart';
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
  required CenterType centerType,
  bool isCaregiverOnly = false,
}) {
  // El CUIDADOR (Fase 3) es EXCLUSIVO: su única área es su monitoreo (/caregiver). Al
  // absorber la lista de AppShell en esta declaración (§5 etapa 5, condición de salida:
  // _itemsFor se retira ENTERO), el caso del cuidador vive aquí, no en una rama especial
  // de AppShell. Con él, el resto se oculta — un solo destino, sin barra ni riel (la
  // regla de ≥2 de NavigationBar/Rail hace el resto). app_shell.dart:54-58.
  NavDestination mod(ModuleKey m, IconData icon, {bool isPrimary = false}) =>
      NavDestination(
        label: m.label,
        icon: icon,
        route: m.route,
        isPrimary: isPrimary,
        visibleWhen: () => moduleEnabled(m.dbValue) && !isCaregiverOnly,
      );

  // Agenda: en HOSPITAL el eje es la RONDA de prevención (tareas que siguen al
  // paciente), no las citas: enruta a /prevention-agenda con etiqueta "Rondas",
  // gateada por prevención. En los demás tipos, la agenda de citas (/agenda), gateada
  // por agenda. Copiado de app_shell.dart:68-79 — sin esta rama, un hospital caía en
  // /agenda "no configurada". Es PRIMARIA en la barra inferior (antes en primaryPaths).
  final NavDestination agendaSlot = centerType == CenterType.hospital
      ? NavDestination(
          label: 'Rondas',
          icon: Icons.checklist_outlined,
          route: '/prevention-agenda',
          isPrimary: true,
          visibleWhen: () =>
              moduleEnabled(ModuleKey.prevention.dbValue) && !isCaregiverOnly,
        )
      : NavDestination(
          label: 'Agenda',
          icon: Icons.calendar_today_outlined,
          route: '/agenda',
          isPrimary: true,
          visibleWhen: () =>
              moduleEnabled(ModuleKey.agenda.dbValue) && !isCaregiverOnly,
        );

  return [
    // Monitoreo (cuidador): su única pantalla. Visible SOLO para el cuidador exclusivo;
    // para todos los demás, oculta. Va primero para que, en el caso improbable de
    // acompañarse de otro destino, ancle abajo. app_shell.dart:54-58.
    NavDestination(
      label: 'Monitoreo',
      icon: Icons.monitor_heart_outlined,
      route: '/caregiver',
      isPrimary: true,
      visibleWhen: () => isCaregiverOnly,
    ),
    // Inicio (dashboard): destino clínico de primer nivel salvo para el master, que
    // no tiene datos clínicos propios (0012). app_shell.dart:63 (siempre, no-master).
    NavDestination(
      label: 'Inicio',
      icon: Icons.dashboard_outlined,
      route: '/',
      isPrimary: true,
      visibleWhen: () => !isMaster && !isCaregiverOnly,
    ),
    mod(ModuleKey.patients, Icons.people_outline,
        isPrimary: true), // app_shell.dart:65 (primaryPaths)
    agendaSlot, // app_shell.dart:68-79
    mod(ModuleKey.prevention, Icons.shield_outlined), // app_shell.dart:80 (/risk)
    mod(ModuleKey.vac, Icons.healing_outlined), // app_shell.dart:83
    mod(ModuleKey.reports, Icons.bar_chart_outlined), // app_shell.dart:86
    mod(ModuleKey.insumos, Icons.medical_services_outlined), // app_shell.dart:89
    mod(ModuleKey.comercial, Icons.point_of_sale_outlined), // app_shell.dart:93
    // Importar expedientes: módulo clínico Y destino del master (antes vivía en la
    // tira externa de /platform). Visible si el módulo está encendido o si es master.
    NavDestination(
      label: ModuleKey.ekare.label,
      icon: Icons.file_upload_outlined,
      route: ModuleKey.ekare.route,
      visibleWhen: () =>
          (moduleEnabled(ModuleKey.ekare.dbValue) || isMaster) &&
          !isCaregiverOnly,
    ),
    NavDestination(
      label: 'Administración',
      icon: Icons.settings_outlined,
      route: '/admin',
      visibleWhen: () => isAdmin && !isCaregiverOnly,
      // Las seis secciones reales de AdminHomeScreen, en su orden.
      children: const [
        NavDestination(
            label: 'Usuarios',
            icon: Icons.people_outline,
            route: '/admin/usuarios'),
        NavDestination(
            label: 'Personal',
            icon: Icons.medical_services_outlined,
            route: '/admin/personal'),
        NavDestination(
            label: 'Sitios',
            icon: Icons.location_on_outlined,
            route: '/admin/sitios'),
        NavDestination(
            label: 'Configuración',
            icon: Icons.settings_outlined,
            route: '/admin/configuracion'),
        NavDestination(
            label: 'Marca',
            icon: Icons.palette_outlined,
            route: '/admin/marca'),
        NavDestination(
            label: 'Licencias',
            icon: Icons.card_membership_outlined,
            route: '/admin/licencias'),
      ],
    ),
    // Plataforma: la consola del master. Nueve secciones, cada una con su ruta
    // propia (§5 etapa 2). Sustituye al riel doble + `_tab`/switch de /platform.
    NavDestination(
      label: 'Plataforma',
      icon: Icons.hub_outlined,
      route: '/platform',
      visibleWhen: () => isMaster && !isCaregiverOnly,
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

/// El riel del master en /platform: sus destinos de primer nivel — "Plataforma"
/// (con sus nueve secciones) y "Importar expedientes", hermanos — sacados de la
/// MISMA declaración de [kuraNavDestinations] (filtrada a lo visible para el master).
/// Plataforma va primero. Es el ÚNICO riel de la pantalla: AppShell no pinta el suyo
/// en /platform (ver appShellShowsOwnNav).
List<NavDestination> platformNavDestinations() {
  final visible = kuraNavDestinations(
    moduleEnabled: (_) => false,
    isAdmin: false,
    isMaster: true,
    // El master no tiene tipo de centro propio; los módulos van ocultos igual, así que
    // la rama de agenda no afecta su riel.
    centerType: CenterType.clinicaHeridas,
  ).where((d) => d.isVisible).toList();
  final plataforma = visible.firstWhere((d) => d.route == '/platform');
  final rest = visible.where((d) => d.route != '/platform');
  return [plataforma, ...rest];
}
