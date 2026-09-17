import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/kura_error_state.dart';
import '../../core/config/app_config.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show KuraAccountMenu, hasNavRail;
import '../support/support_launcher.dart';
import '../../core/nav/kura_nav_rail.dart';
import '../../core/nav/kura_nav_destinations.dart';
import '../../core/nav/section_action.dart';
import 'license_panel.dart';
import 'users_screen.dart';
import 'staff_screen.dart';
import 'sites_screen.dart';
import 'note_catalog_screen.dart';
import 'branding_screen.dart';
// Las 8 pantallas profundas de /admin, ahora cuerpos dentro del shell.
import 'protocol_kura_screen.dart';
import 'protocol_matrix_screen.dart';
import 'scale_toggles_screen.dart';
import 'recommendations_reference_screen.dart';
import 'acuity_session_type_screen.dart';
import 'acuity_visit_type_map_screen.dart';
import 'data_disclosures_screen.dart';
import 'patient_cleanup_screen.dart';
import '../../models/module_key.dart';

/// Panel de administración: gestión de personal sanitario, sitios y
/// activación de usuarios / función premium (sección 4).
/// SHELL de las secciones de Administración: pinta el riel único (KuraNavRail) y, en
/// colapsado, el menú del encabezado; el cuerpo de la sección llega como [child].
/// Vive en un ShellRoute ANIDADO, así que cambiar de sección NO reconstruye el riel —
/// solo cambia el child. Se ve como cambiar de panel, no como cargar otra página.
class AdminSectionsShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentRoute; // /admin/<section>
  const AdminSectionsShell(
      {super.key, required this.child, required this.currentRoute});

  @override
  ConsumerState<AdminSectionsShell> createState() =>
      _AdminSectionsShellState();
}

class _AdminSectionsShellState extends ConsumerState<AdminSectionsShell> {
  // Colapso MANUAL del riel. null = seguir el ancho (auto); true/false = elección
  // del usuario. Vive en el State del shell, que persiste en el ShellRoute, así que
  // la elección sobrevive a los cambios de sección.
  bool? _userCollapsed;

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final currentRoute = widget.currentRoute;
    // Guarda de rol (2ª capa; el redirect del router es la 1ª). En web una URL
    // no es candado: solo admin del centro y master ven Administración. Un
    // clinico que llegue aquí por cualquier ruta no ve nada administrativo.
    final sessionUser = ref.watch(sessionProvider).user;
    if (sessionUser != null && !sessionUser.isAdmin && !sessionUser.isMaster) {
      return const Scaffold(
        body: Center(child: Text('No tienes acceso a esta sección.')),
      );
    }
    // Riel abierto ≥1200 px por defecto (§2.1/§2.2); el botón de colapsar/expandir
    // manda por encima del ancho una vez que el usuario lo toca.
    final autoCollapsed = MediaQuery.of(context).size.width < 1200;
    final collapsed = _userCollapsed ?? autoCollapsed;
    // Administración SIEMPRE pinta un riel (abierto o colapsado, nunca barra inferior),
    // así que aquí siempre hay riel: TourScope no duplica el flotante de Ayuda.
    publishRailPresent(ref, true, mounted: () => mounted);
    // UN solo riel: la MISMA declaración de la app, con los destinos clínicos de
    // primer nivel y Administración anidando sus seis secciones.
    final modules = ref.watch(enabledModulesProvider);
    final navs = kuraNavDestinations(
      moduleEnabled: (k) => modules.any((m) => m.dbValue == k),
      // Rol REAL de la sesión, como en AppShell: con isMaster clavado en false, un master
      // que entraba a Administración perdía el destino Plataforma y ganaba Inicio —un riel
      // distinto del que traía (§13.3). La guarda de rol de arriba ya deja pasar a admin Y a
      // master, así que esto NO cambia quién entra, solo qué riel ve.
      isAdmin: sessionUser?.isAdmin ?? false,
      isMaster: sessionUser?.isMaster ?? false,
      // Tipo de centro activo: define la rama de agenda (hospital → Rondas).
      centerType: ref.watch(sessionProvider).activeCenterType,
    );
    final admin = navs.firstWhere((d) => d.route == '/admin');

    // SIN AppBar: el encabezado vive DENTRO del área de contenido (canvas). El nombre
    // de la sección sale una sola vez, ahí. En angosto ese mismo encabezado lleva el
    // menú Sección › Subsección ▾. Administración no tiene acciones (la identidad se
    // eliminó: el pie del riel ya dice quién eres y en qué centro).
    final content = Column(
      children: [
        KuraContentHeader(
          section: admin,
          currentRoute: currentRoute,
          collapsed: collapsed,
          // A ≥900 px la acción principal de la sección va aquí (sólida), no en un FAB.
          actions: sectionHeaderActions(ref, currentRoute,
              hasRail: hasNavRail(ref, context)),
        ),
        const Divider(height: 1),
        Expanded(child: child),
      ],
    );
    return Scaffold(
      body: Row(
        children: [
          KuraNavRail(
            destinations: navs,
            currentRoute: currentRoute,
            collapsed: collapsed,
            brandName: 'KuraTracker',
            userName: sessionUser?.fullName,
            centerName: 'Administración',
            onToggleCollapse: () =>
                setState(() => _userCollapsed = !collapsed),
            // El pie del riel es el menú de cuenta (cerrar sesión, etc.): al quitar
            // el AppBar se fue el UserMenuButton, así que la identidad ES el control.
            accountMenuBuilder: (ctx, child) => KuraAccountMenu(child: child),
            onHelp: AppConfig.isSupabaseConfigured
                ? () => openSupportAssistant(ref)
                : null,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// El CUERPO de una sección de Administración (solo el panel, sin riel). Lo construye
/// cada ruta de sección con NoTransitionPage — cambiar de sección no navega, cambia el
/// panel dentro del mismo shell.
class AdminSectionBody extends ConsumerWidget {
  final String section;
  const AdminSectionBody({super.key, required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final sessionUser = ref.watch(sessionProvider).user;
    // organizationId/currentUserId del admin en sesión, acotan las altas al centro.
    final organizationId = sessionUser?.organizationId;
    final currentUserId = sessionUser?.id;
    return repoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: KuraErrorState(
            title: 'No pudimos cargar la administración',
            reassurance:
                'Puede ser tu conexión. Tus datos están a salvo: nada se '
                'perdió ni se guardó a medias.',
            detail: '$e',
            onRetry: () => ref.invalidate(dataRepositoryProvider),
          ),
        ),
      ),
      data: (repo) {
        switch (section) {
          case 'personal':
            return StaffScreen(repo: repo, organizationId: organizationId);
          case 'sitios':
            return SitesScreen(repo: repo, organizationId: organizationId);
          case 'configuracion':
            return NoteCatalogScreen(repo: repo, organizationId: organizationId);
          case 'marca':
            return repo.premiumAdminFor(organizationId)
                ? BrandingScreen(repo: repo, organizationId: organizationId)
                : const _AdminModuleLocked('La personalización de marca');
          case 'licencias':
            return LicensePanel(
                repo: repo, organizationId: organizationId, user: sessionUser);
          // Las 8 profundas — cuerpos (sin Scaffold). Cada una aplica su propio
          // candado comercial (y el master lo trasciende). El shell pone el título
          // (lo deriva del label del riel) y el riel.
          case 'protocolo-kura':
            return ProtocolKuraScreen(repo: repo, organizationId: organizationId);
          case 'productos-protocolo':
            return ProtocolMatrixScreen(
                repo: repo, organizationId: organizationId);
          case 'escalas-protocolo':
            return ScaleTogglesScreen(
                repo: repo, organizationId: organizationId);
          case 'fuente-recomendaciones':
            return const RecommendationsReferenceScreen();
          case 'tipo-cita-sesiones':
            return AcuitySessionTypeScreen(
                repo: repo, organizationId: organizationId);
          case 'tipos-consulta':
            return AcuityVisitTypeMapScreen(
                repo: repo, organizationId: organizationId);
          case 'divulgaciones':
            return const DataDisclosuresScreen();
          case 'depurar-expedientes':
            return PatientCleanupScreen(
                repo: repo, organizationId: organizationId);
          default:
            return UsersScreen(
                repo: repo,
                organizationId: organizationId,
                currentUserId: currentUserId);
        }
      },
    );
  }
}

/// Pantalla completa detrás del módulo Administración (avanzado): reemplaza el
/// contenido de una pestaña cuando el centro no lo tiene (p. ej. Marca).
class _AdminModuleLocked extends StatelessWidget {
  final String feature;
  const _AdminModuleLocked(this.feature);
  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_outlined,
                  color: t.statusWarningText),
              const SizedBox(height: 8),
              Text(
                '$feature es parte del módulo Administración avanzada.\n'
                'Solicítalo a tu administrador de plataforma para habilitarlo.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
  }
}

