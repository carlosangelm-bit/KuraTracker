import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../../features/support/support_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens.dart';
import '../providers/session_provider.dart';
import '../widgets/kura_glass_card.dart';
import '../../models/app_user.dart';
import '../../models/center_type.dart';
import '../../models/module_key.dart';
import '../../services/data_repository.dart';

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

  List<_NavItem> _itemsFor(
      AppUser? user, Set<ModuleKey> modules, CenterType centerType) {
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

    // El cuidador (Fase 3) tiene una sola área: su monitoreo (pacientes
    // asignados, solo lectura, + sus tareas preventivas). RESTRICCIÓN → cuidador
    // EXCLUSIVO (punto 6 §0): la nav reducida es solo para quien no tiene nada
    // más amplio.
    if (user?.isCaregiverOnly ?? false) {
      return const [
        _NavItem('/caregiver', Icons.monitor_heart_outlined, Icons.monitor_heart, 'Monitoreo'),
      ];
    }

    // Inicio siempre visible. Los demás items clínicos se muestran solo si su
    // módulo está habilitado para el centro/sitio/usuario (Fase 2). Apagar un
    // módulo solo lo oculta; sus datos permanecen.
    final items = <_NavItem>[
      const _NavItem('/', Icons.dashboard_outlined, Icons.dashboard, 'Inicio'),
    ];
    if (modules.contains(ModuleKey.patients)) {
      items.add(const _NavItem('/patients', Icons.people_outline, Icons.people, 'Pacientes'));
    }
    // Agenda: en HOSPITAL el eje es la RONDA de prevención (tareas que siguen al
    // paciente, no citas externas). La agenda de citas (modelo Acuity) es propia
    // de la clínica de heridas, así que en hospital la pestaña de agenda enruta a
    // las rondas de prevención en vez de a /agenda (que saldría "no configurada").
    if (centerType == CenterType.hospital) {
      if (modules.contains(ModuleKey.prevention)) {
        items.add(const _NavItem(
            '/prevention-agenda', Icons.checklist_outlined, Icons.checklist, 'Rondas'));
      }
    } else if (modules.contains(ModuleKey.agenda)) {
      items.add(const _NavItem('/agenda', Icons.event_outlined, Icons.event, 'Agenda'));
    }
    if (modules.contains(ModuleKey.prevention)) {
      items.add(const _NavItem('/risk', Icons.shield_outlined, Icons.shield, 'Prevención'));
    }
    if (modules.contains(ModuleKey.vac)) {
      items.add(const _NavItem('/vac', Icons.healing_outlined, Icons.healing, 'VAC'));
    }
    if (modules.contains(ModuleKey.reports)) {
      items.add(const _NavItem('/reports', Icons.description_outlined, Icons.description, 'Reportes'));
    }
    if (modules.contains(ModuleKey.insumos)) {
      items.add(const _NavItem(
          '/insumos', Icons.medical_services_outlined, Icons.medical_services, 'Insumos'));
    }
    if (modules.contains(ModuleKey.comercial)) {
      items.add(const _NavItem(
          '/comercial', Icons.point_of_sale_outlined, Icons.point_of_sale, 'Comercial'));
    }
    if (user?.role == AppRole.admin) {
      items.add(const _NavItem(
          '/admin', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, 'Administración'));
    }
    if (modules.contains(ModuleKey.ekare)) {
      items.add(const _NavItem('/import-export', Icons.sync_alt_outlined, Icons.sync_alt, 'eKare'));
    }
    return items;
  }

  int _indexFor(String path, List<_NavItem> items) {
    return _indexForOrNull(path, items) ?? 0;
  }

  /// Como [_indexFor] pero devuelve null si la ruta no corresponde a ningún
  /// item (para poder resaltar "Más" en la barra móvil).
  int? _indexForOrNull(String path, List<_NavItem> items) {
    for (var i = 0; i < items.length; i++) {
      if (path == items[i].path ||
          (items[i].path != '/' && path.startsWith(items[i].path))) {
        return i;
      }
    }
    return null;
  }

  /// Menú "Más" (móvil): el resto de las secciones que no caben abajo.
  void _showMoreMenu(BuildContext context, List<_NavItem> overflow) {
    final t = BrandTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final i in overflow)
              ListTile(
                leading: Icon(i.selectedIcon, color: t.brandPrimary),
                title: Text(i.label),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.go(i.path);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final modules = ref.watch(enabledModulesProvider);
    final items = _itemsFor(session.user, modules, session.activeCenterType);
    final selectedIndex = _indexFor(currentPath, items);
    final isWide = MediaQuery.of(context).size.width >= 900;
    // La barra flotante solo se muestra en pantallas de NIVEL SUPERIOR (las
    // pestañas). En pantallas "profundas" (detalle de paciente, formularios,
    // captura, seguimiento…) se oculta: son flujos con botón de regresar y, al
    // vivir en el mismo Scaffold-shell con extendBody, la barra taparía sus
    // botones inferiores. Así ningún botón queda cubierto en ninguna pantalla.
    final isTopLevel = items.any((i) => i.path == currentPath);
    final t = BrandTokens.of(context);

    final destinationsRail = items
        .map((i) => NavigationRailDestination(
              icon: Icon(i.icon),
              selectedIcon: Icon(i.selectedIcon),
              label: Text(i.label),
            ))
        .toList();

    void onSelect(int index) => context.go(items[index].path);

    // --- Barra inferior (MÓVIL): solo los indispensables + "Más" ---
    // Se dejan abajo Inicio, Pacientes y Agenda/Rondas; el resto de los módulos
    // (Prevención, VAC, Reportes, Insumos, Comercial, Administración, eKare) va
    // a un menú "Más". Solo se usa el menú si hay primarios que anclar y ≥2 en
    // el resto (roles con pocos items —master/cuidador— muestran todo directo).
    const primaryPaths = ['/', '/patients', '/agenda', '/prevention-agenda'];
    final primary =
        items.where((i) => primaryPaths.contains(i.path)).toList();
    final overflow =
        items.where((i) => !primaryPaths.contains(i.path)).toList();
    final useMore = primary.isNotEmpty && overflow.length >= 2;
    final mobileItems = useMore ? primary : items;
    final mobileDestinations = <NavigationDestination>[
      for (final i in mobileItems)
        NavigationDestination(
            icon: Icon(i.icon),
            selectedIcon: Icon(i.selectedIcon),
            label: i.label),
      if (useMore)
        const NavigationDestination(
            icon: Icon(Icons.menu),
            selectedIcon: Icon(Icons.menu),
            label: 'Más'),
    ];
    final mobileIdx = _indexForOrNull(currentPath, mobileItems);
    final mobileSelectedIndex =
        mobileIdx ?? (useMore ? mobileItems.length : 0);
    void mobileOnSelect(int index) {
      if (useMore && index == mobileItems.length) {
        _showMoreMenu(context, overflow);
      } else {
        context.go(mobileItems[index].path);
      }
    }

    return Scaffold(
      // El contenido pasa por DEBAJO de la barra flotante (para que el vidrio
      // lo refracte). Las pantallas scrolleables compensan con padding inferior
      // (ver kFloatingNavBarHeight / MediaQuery.padding.bottom).
      extendBody: true,
      // Sin AppBar del shell: UNA sola barra por pantalla. Cada pantalla de
      // nivel superior ya trae su propio AppBar con su titulo e incluye el
      // avatar/menu de usuario en sus acciones ([UserMenuButton]); el dashboard
      // lo lleva en su encabezado. En escritorio el menu vive en el
      // NavigationRail. Esto elimina la doble barra en movil.
      appBar: null,
      body: _SyncBanner(
        child: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelect,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: _brandTitle(context, ref, session, compact: true),
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
      ),
      // Barra de navegacion FLOTANTE estilo "liquid glass": no pegada a los
      // bordes (margen + esquinas casi pildora), acabado de vidrio consistente
      // con KuraGlassCard y sombra en capas para verse despegada del fondo.
      bottomNavigationBar: (isWide || !isTopLevel)
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
                      selectedIndex: mobileSelectedIndex,
                      onDestinationSelected: mobileOnSelect,
                      destinations: mobileDestinations,
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

  Widget _brandTitle(BuildContext context, WidgetRef ref, SessionState session,
      {bool compact = false}) {
    final t = BrandTokens.of(context);
    final canSwitch = session.canSwitchCenter;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: t.brandPrimary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.healing, color: Colors.white, size: 20),
        ),
        if (!compact) ...[
          const SizedBox(width: 8),
          Text('KuraTracker',
              style: TextStyle(fontWeight: FontWeight.w800, color: t.textPrimary)),
        ],
        // Indicador de que el ícono es un switcher cuando hay varios centros.
        if (canSwitch)
          Icon(Icons.unfold_more, size: 16, color: t.textSecondary),
      ],
    );
    if (!canSwitch) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showCenterSwitcher(context, ref),
      child: Padding(padding: const EdgeInsets.all(4), child: row),
    );
  }

  Widget _userMenu(BuildContext context, WidgetRef ref, SessionState session,
      {bool vertical = false}) {
    final user = session.user;
    if (user == null) return const SizedBox.shrink();
    final t = BrandTokens.of(context);
    return PopupMenuButton<String>(
      tooltip: user.fullName,
      onSelected: (value) {
        if (value == 'logout') {
          ref.read(sessionProvider.notifier).logout();
          context.go('/login');
        } else if (value == 'switch') {
          showCenterSwitcher(context, ref);
        } else if (value == 'help') {
          openSupportAssistant(ref);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        PopupMenuItem(enabled: false, child: Text(user.role.label)),
        const PopupMenuDivider(),
        if (AppConfig.isSupabaseConfigured)
          const PopupMenuItem(value: 'help', child: Text('Asistente de ayuda')),
        if (session.canSwitchCenter)
          const PopupMenuItem(value: 'switch', child: Text('Cambiar de centro')),
        const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
      ],
      child: CircleAvatar(
        backgroundColor: t.brandPrimary.withOpacity(0.15),
        child: Text(
          user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
          style: TextStyle(color: t.brandPrimary, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Color de marca asociado a un tipo de centro (para los chips del switcher).
Color centerTypeColor(CenterType type) => BrandTokens.forCenterType(type).brandPrimary;

/// Abre el selector de centro (switcher del ícono de apósitos / menú de
/// usuario). Lista las membresías del usuario con su nombre y un chip de tipo
/// coloreado; al elegir uno, cambia el centro activo (repinta la paleta).
Future<void> showCenterSwitcher(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionProvider);
  final user = session.user;
  if (user == null || !session.canSwitchCenter) return;
  final repo = await DataRepository.instance();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) {
      final t = BrandTokens.of(sheetCtx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Cambiar de centro',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: t.textPrimary)),
            ),
            ...session.memberships.map((m) {
              final org = repo.organizationById(m.organizationId);
              final type = org?.centerType ?? CenterType.clinicaHeridas;
              final isActive = m.organizationId == user.organizationId;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: centerTypeColor(type).withOpacity(0.15),
                  child: Icon(Icons.healing, color: centerTypeColor(type), size: 20),
                ),
                title: Text(org?.name ?? 'Centro'),
                subtitle: Text('${type.label} · ${m.role.label}'),
                trailing: isActive
                    ? Icon(Icons.check_circle, color: t.brandPrimary)
                    : null,
                onTap: isActive
                    ? null
                    : () async {
                        Navigator.of(sheetCtx).pop();
                        final ok = await ref
                            .read(sessionProvider.notifier)
                            .switchCenter(m.organizationId);
                        if (context.mounted && !ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('No se pudo cambiar de centro')),
                          );
                        }
                      },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

class _NavItem {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.path, this.icon, this.selectedIcon, this.label);
}

/// Menú de usuario (avatar + cerrar sesión) para los AppBar de las pantallas.
/// Al quitar el AppBar del shell (una sola barra por pantalla), cada pantalla
/// de nivel superior lo incluye en sus `actions` para conservar el acceso a
/// cerrar sesión en móvil.
/// Banda superior que avisa cuántas escrituras quedaron sin sincronizar
/// (offline-first, Fase 1). Solo aparece cuando hay pendientes; permite forzar
/// la sincronización. En modo demo/local no aparece (no hay cola).
class _SyncBanner extends ConsumerWidget {
  final Widget child;
  const _SyncBanner({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(dataRepositoryProvider).valueOrNull;
    final writesPending = repo?.pendingSyncCount;
    final photosPending = repo?.photoPendingCount;
    final writesFailed = repo?.writeFailedCount;
    final photosFailed = repo?.photoFailedCount;
    if (repo == null ||
        writesPending == null ||
        photosPending == null ||
        writesFailed == null ||
        photosFailed == null) {
      return child;
    }
    return Column(
      children: [
        AnimatedBuilder(
          animation: Listenable.merge(
              [writesPending, photosPending, writesFailed, photosFailed]),
          builder: (context, _) {
            final pending = writesPending.value + photosPending.value;
            final failed = writesFailed.value + photosFailed.value;
            if (pending + failed <= 0) return const SizedBox.shrink();
            final hasFailed = failed > 0;
            final base = hasFailed ? Colors.red : Colors.orange;
            final parts = <String>[
              if (pending > 0) '$pending pendiente(s)',
              if (failed > 0) '$failed con problema(s)',
            ];
            return Material(
              color: base.shade100,
              child: InkWell(
                onTap: () => _showSyncSheet(context, repo),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                    child: Row(
                      children: [
                        Icon(
                            hasFailed
                                ? Icons.error_outline
                                : Icons.cloud_off_outlined,
                            size: 16,
                            color: base.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${parts.join(' · ')} de sincronización · toca para ver',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: base.shade900),
                          ),
                        ),
                        if (!hasFailed)
                          TextButton(
                            onPressed: () => repo.syncOfflineNow(),
                            child: const Text('Sincronizar'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        Expanded(child: child),
      ],
    );
  }

  Future<void> _showSyncSheet(BuildContext context, DataRepository repo) async {
    final failedWrites = repo.failedDescriptions();
    final failedPhotos = await repo.failedPhotoDescriptions();
    final failed = [...failedWrites, ...failedPhotos];
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Sincronización offline',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'Los cambios y fotos capturados sin conexión se suben solos al '
              'reconectar. Aquí puedes forzar el intento o gestionar los que '
              'dieron problema.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar ahora'),
              onPressed: () {
                repo.syncOfflineNow();
                Navigator.of(ctx).pop();
              },
            ),
            if (failed.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Con problema (${failed.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'No se pudieron subir (rechazo del servidor o conflicto con un '
                'cambio hecho por otra persona). No se sobrescribió nada.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in failed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(f,
                                      style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        repo.retryFailedOffline();
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Reintentar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red),
                      onPressed: () async {
                        await repo.discardFailedOffline();
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: const Text('Descartar'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class UserMenuButton extends ConsumerWidget {
  const UserMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    if (user == null) return const SizedBox.shrink();
    final t = BrandTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: user.fullName,
        onSelected: (value) {
          if (value == 'logout') {
            ref.read(sessionProvider.notifier).logout();
            context.go('/login');
          } else if (value == 'switch') {
            showCenterSwitcher(context, ref);
          } else if (value == 'help') {
            openSupportAssistant(ref);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: false,
            child: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          PopupMenuItem(enabled: false, child: Text(user.role.label)),
          const PopupMenuDivider(),
          if (AppConfig.isSupabaseConfigured)
            const PopupMenuItem(value: 'help', child: Text('Asistente de ayuda')),
          if (session.canSwitchCenter)
            const PopupMenuItem(value: 'switch', child: Text('Cambiar de centro')),
          const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
        ],
        child: CircleAvatar(
          radius: 16,
          backgroundColor: t.brandPrimary.withOpacity(0.15),
          child: Text(
            user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
            style: TextStyle(color: t.brandPrimary, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
