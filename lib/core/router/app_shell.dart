import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../../features/support/support_launcher.dart';
import '../../features/auth/demo_reset_action.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens.dart';
import '../providers/session_provider.dart';
import '../widgets/kura_glass_card.dart';
import '../nav/kura_nav_destinations.dart';
import '../nav/kura_nav_rail.dart';
import '../nav/nav_destination.dart';
import 'shell_nav_visibility.dart';
import '../../models/app_user.dart';
import '../../models/center_type.dart';
import '../../models/module_key.dart';
import '../../services/data_repository.dart';
import '../name_format.dart';

/// Alto del contenido de la barra de navegacion flotante. Las pantallas
/// scrolleables del shell suman esto (mas el inset inferior del sistema) a su
/// padding inferior para que el ultimo elemento no quede tapado por la barra.
/// Con `extendBody: true`, el Scaffold ya expone este alto en
/// `MediaQuery.of(context).padding.bottom` del body.
const double kFloatingNavBarHeight = 64;

/// Shell de navegacion principal de las rutas clínicas. Pinta el riel único
/// [KuraNavRail] en escritorio (TRES bandas de ancho) y la barra flotante en móvil,
/// AMBOS derivados de la MISMA declaración [kuraNavDestinations] — ya no hay una
/// segunda lista de destinos (`_itemsFor`) que sincronizar a mano. Ésa duplicación
/// costó la regresión del hospital viendo /agenda; §5 etapa 5 la retira.
///
/// Tres bandas (§2): ancho ≥ 1200 → riel ABIERTO; 900–1199 → riel COLAPSADO;
/// < 900 → sin riel, con la barra inferior flotante (los tres desde la declaración).
/// En /platform y /admin NO pinta su navegación (esas pantallas traen su propio
/// KuraNavRail); ver [appShellShowsOwnNav].
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentPath;

  const AppShell({super.key, required this.child, required this.currentPath});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // Colapso MANUAL del riel de escritorio. null = seguir el ancho (auto); en cuanto
  // el usuario toca el chevron, su elección manda por encima del ancho. Vive en el
  // State para sobrevivir a los rebuilds del shell.
  bool? _userCollapsed;

  /// Índice del destino cuya ruta corresponde a [path] dentro de [items] (o null si
  /// ninguno: sirve para resaltar "Más" en la barra móvil). Un destino de ruta `r`
  /// captura `r` y sus rutas hijas `r/…` (salvo `/`, que solo se captura exacto).
  int? _indexOf(List<NavDestination> items, String path) {
    for (var i = 0; i < items.length; i++) {
      final r = items[i].route;
      if (path == r || (r != '/' && path.startsWith(r))) return i;
    }
    return null;
  }

  /// Menú "Más" (móvil): el resto de los destinos que no caben abajo.
  void _showMoreMenu(BuildContext context, List<NavDestination> overflow) {
    final t = BrandTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in overflow)
              ListTile(
                leading: Icon(d.icon, color: t.brandPrimary),
                title: Text(d.label),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.go(d.route);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final modules = ref.watch(enabledModulesProvider);
    final user = session.user;
    final currentPath = widget.currentPath;
    final child = widget.child;
    final t = BrandTokens.of(context);

    // ÚNICA fuente de destinos (§5 etapa 5): la declaración. Reemplaza _itemsFor.
    // El cuidador exclusivo y el master salen de aquí, no de una rama especial.
    final navs = kuraNavDestinations(
      moduleEnabled: (k) => modules.any((m) => m.dbValue == k),
      isAdmin: user?.isAdmin ?? false,
      isMaster: user?.isMaster ?? false,
      centerType: session.activeCenterType,
      isCaregiverOnly: user?.isCaregiverOnly ?? false,
    );
    final visibleTop = navs.where((d) => d.isVisible).toList();

    final width = MediaQuery.of(context).size.width;
    // En /platform y /admin AppShell no pinta su navegación: esas pantallas traen su
    // propio KuraNavRail (evita dos rieles y doble marca de activo).
    final showOwnNav = appShellShowsOwnNav(currentPath);
    // La barra inferior solo se muestra en pantallas de NIVEL SUPERIOR (los destinos).
    // En pantallas "profundas" (detalle, formularios, captura…) se oculta: son flujos
    // con botón de regresar y, con extendBody, la barra taparía sus botones. El riel de
    // escritorio SÍ se mantiene en profundas (como antes), con el destino padre activo.
    final isTopLevel = visibleTop.any((d) => navRouteIsActive(d, currentPath));

    // --- Riel de escritorio (KuraNavRail): TRES bandas -----------------------
    // ≥1200 abierto; 900–1199 colapsado; <900 no hay riel (barra inferior). Requiere
    // ≥2 destinos: KuraNavRail (como NavigationRail/Bar) no tiene sentido con uno solo
    // —un cuidador tiene una sola pantalla y queda sin riel y sin barra, y está bien.
    final showRail = width >= 900 && showOwnNav && visibleTop.length >= 2;
    final autoCollapsed = width < 1200;
    final collapsed = _userCollapsed ?? autoCollapsed;

    // --- Barra inferior (MÓVIL): primarios + "Más", desde la MISMA declaración ---
    // Los primarios (isPrimary: Inicio, Pacientes, Agenda/Rondas) anclan abajo; el
    // resto va al menú "Más". Solo se usa "Más" si hay primarios que anclar y ≥2 en el
    // resto (roles con pocos destinos muestran todo directo).
    final split = navBottomBarSplit(navs);
    final useMore = split.primary.isNotEmpty && split.overflow.length >= 2;
    final mobileItems = useMore ? split.primary : visibleTop;
    final mobileDestinations = <NavigationDestination>[
      for (final d in mobileItems)
        NavigationDestination(
            icon: Icon(d.icon), selectedIcon: Icon(d.icon), label: d.label),
      if (useMore)
        const NavigationDestination(
            icon: Icon(Icons.menu), selectedIcon: Icon(Icons.menu), label: 'Más'),
    ];
    final mobileIdx = _indexOf(mobileItems, currentPath);
    final mobileSelectedIndex = mobileIdx ?? (useMore ? mobileItems.length : 0);
    void mobileOnSelect(int index) {
      if (useMore && index == mobileItems.length) {
        _showMoreMenu(context, split.overflow);
      } else {
        context.go(mobileItems[index].route);
      }
    }

    return Scaffold(
      // El contenido pasa por DEBAJO de la barra flotante (para que el vidrio lo
      // refracte). Las pantallas scrolleables compensan con padding inferior (ver
      // kFloatingNavBarHeight / MediaQuery.padding.bottom).
      extendBody: true,
      // Sin AppBar del shell: UNA sola barra por pantalla. Cada pantalla de nivel
      // superior trae su propio AppBar con su título y su acceso a cuenta; en el riel
      // de escritorio, la cuenta vive en el pie (KuraAccountMenu vía accountMenuBuilder).
      appBar: null,
      body: _SyncBanner(
        child: showRail
            ? Row(
                children: [
                  KuraNavRail(
                    destinations: navs,
                    currentRoute: currentPath,
                    collapsed: collapsed,
                    brandName: 'KuraTracker',
                    userName: user?.fullName,
                    onToggleCollapse: () =>
                        setState(() => _userCollapsed = !collapsed),
                    // El pie del riel es el menú de cuenta (cerrar sesión, cambiar de
                    // centro, ayuda): identidad = control, como en /admin y /platform.
                    accountMenuBuilder: (ctx, child) =>
                        KuraAccountMenu(child: child),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              )
            : child,
      ),
      // Barra de navegacion FLOTANTE estilo "liquid glass": no pegada a los bordes
      // (margen + esquinas casi pildora), acabado de vidrio consistente con
      // KuraGlassCard. Solo en móvil (<900), en pantallas de nivel superior, con ≥2
      // destinos y donde AppShell pinta su nav.
      bottomNavigationBar: (width >= 900 ||
              !isTopLevel ||
              mobileDestinations.length < 2 ||
              !showOwnNav)
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
    final orgId = ref.watch(sessionProvider).user?.organizationId;
    final readOnlyReason = repo.clinicalReadOnlyReason(orgId);
    final isAdmin = ref.watch(sessionProvider).user?.isAdmin ?? false;
    return Column(
      children: [
        if (readOnlyReason != null)
          _ReadOnlyBand(reason: readOnlyReason, showCta: isAdmin),
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

/// Banda de MODO LECTURA: el centro puede leer su expediente pero no escribir
/// (pago vencido, prueba terminada, suscripción no vigente). Explica el motivo —un
/// expediente que se lee pero no se escribe sin explicación se reporta como app
/// rota— y, para el admin, ofrece el atajo a Licencias.
class _ReadOnlyBand extends StatelessWidget {
  final String reason;
  final bool showCta;
  const _ReadOnlyBand({required this.reason, required this.showCta});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade100,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(reason,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade900)),
              ),
              if (showCta)
                TextButton(
                  onPressed: () => context.go('/admin'),
                  child: const Text('Licencias'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menú de cuenta (cerrar sesión, cambiar de centro, ayuda, reiniciar demo)
/// desplegado desde un [child] cualquiera: el avatar de la barra ([UserMenuButton])
/// o el pie del riel de navegación (identidad = control). Reúne en un solo lugar lo
/// que cuelga de la cuenta, para que ningún punto de la app pinte identidad sin dar
/// acceso a cerrar sesión.
class KuraAccountMenu extends ConsumerWidget {
  final Widget child;
  const KuraAccountMenu({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    if (user == null) return child;
    return PopupMenuButton<String>(
      tooltip: user.fullName,
      onSelected: (value) {
        if (value == 'logout') {
          ref.read(sessionProvider.notifier).logout();
          // El destino depende del modo: en la DEMO la landing es el selector
          // de perfiles, no el login de producción (ahí no hay credenciales
          // válidas y el visitante queda en un callejón sin salida, además de
          // perder el acceso al botón "Reiniciar demo", que vive en esa pantalla).
          context.go(AppConfig.isSupabaseConfigured ? '/login' : '/demo');
        } else if (value == 'switch') {
          showCenterSwitcher(context, ref);
        } else if (value == 'help') {
          openSupportAssistant(ref);
        } else if (value == 'reset_demo') {
          showResetDemoDialog(context, ref);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(user.fullName,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        PopupMenuItem(enabled: false, child: Text(user.role.label)),
        const PopupMenuDivider(),
        if (AppConfig.isSupabaseConfigured)
          const PopupMenuItem(value: 'help', child: Text('Asistente de ayuda')),
        if (session.canSwitchCenter)
          const PopupMenuItem(value: 'switch', child: Text('Cambiar de centro')),
        if (!AppConfig.isSupabaseConfigured)
          const PopupMenuItem(
              value: 'reset_demo', child: Text('Reiniciar demo')),
        const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
      ],
      child: child,
    );
  }
}

class UserMenuButton extends ConsumerWidget {
  const UserMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    if (user == null) return const SizedBox.shrink();
    final t = BrandTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: KuraAccountMenu(
        child: CircleAvatar(
          radius: 16,
          backgroundColor: t.brandPrimary.withOpacity(0.15),
          child: Text(
            avatarInitial(user.fullName),
            style: TextStyle(color: t.brandPrimary, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
