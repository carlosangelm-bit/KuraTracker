// § etapa 5 (simetría a) — Transiciones. Con el riel único, moverse entre destinos de
// PRIMER NIVEL es cambiar de PANEL, igual que entre las secciones de /admin y /platform:
// sin animación (NoTransitionPage → transitionDuration == 0). Las rutas PROFUNDAS
// —detalle, formularios, captura— SÍ conservan transición: ahí navegas hacia adentro y
// el movimiento lo comunica.
//
// Se prueba sobre el ROUTER REAL con el mismo criterio que admin_router_real_test:
// ModalRoute.of(pantalla).transitionDuration. Rojo verificado: (1) una clínica de primer
// nivel con `builder:` (animada) declara transición; (2) una ruta profunda con
// NoTransitionPage deja de declararla.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la
// toolchain local (3.44) no compila. `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/features/admin/admin_home_screen.dart' show AdminSectionsShell;
import 'package:kuratracker/features/platform/platform_home_screen.dart'
    show PlatformSectionsShell;
import 'package:kuratracker/features/dashboard/dashboard_screen.dart';
import 'package:kuratracker/features/patients/patients_list_screen.dart';
import 'package:kuratracker/features/patients/patient_form_screen.dart';
import 'package:kuratracker/features/reports/reports_screen.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser user) {
    state = SessionState(user: user);
  }
}

const _admin = AppUser(
  id: 'a1',
  role: AppRole.admin,
  fullName: 'Admin Uno',
  email: 'a@x.test',
  organizationId: 'org-demo',
  staffId: 's1',
);

// El master alcanza /platform; el redirect global rebota a un admin de centro fuera de él.
const _master = AppUser(
  id: 'm1',
  role: AppRole.master,
  fullName: 'Master Uno',
  email: 'm@x.test',
  organizationId: 'org-demo',
  staffId: 's9',
);

Future<GoRouter> _mount(WidgetTester t, {AppUser user = _admin}) async {
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  final repo = await DataRepository.instance();
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => _FakeSession(user)),
    dataRepositoryProvider.overrideWith((ref) => repo),
    enabledModulesProvider.overrideWithValue(const {
      ModuleKey.patients,
      ModuleKey.agenda,
      ModuleKey.reports,
    }),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      routerConfig: router,
    ),
  ));
  await t.pumpAndSettle();
  return router;
}

/// Duración de transición de la página que monta [screen] (la ruta activa).
Duration _transitionOf(WidgetTester t, Type screen) =>
    ModalRoute.of(t.element(find.byType(screen)))!.transitionDuration;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('clínicas de PRIMER NIVEL: sin transición (cambian de panel)', (t) async {
    final router = await _mount(t);

    // Cada destino del riel: cambiar a él no anima (NoTransitionPage → 0).
    final firstLevel = <String, Type>{
      '/': DashboardScreen,
      '/patients': PatientsListScreen,
      '/reports': ReportsScreen,
    };
    for (final entry in firstLevel.entries) {
      router.go(entry.key);
      await t.pumpAndSettle();
      expect(_transitionOf(t, entry.value), Duration.zero,
          reason: '${entry.key} debe ser NoTransitionPage (cambia de panel)');
    }
  });

  testWidgets('ruta PROFUNDA: SÍ declara transición (navegas hacia adentro)', (t) async {
    final router = await _mount(t);

    // /patients/new (formulario) es profunda: conserva la transición por omisión.
    router.go('/patients/new');
    await t.pumpAndSettle();
    expect(_transitionOf(t, PatientFormScreen), isNot(Duration.zero),
        reason: 'una ruta profunda debe conservar su transición');
  });

  // §12: ENTRAR a una consola (Administración / Plataforma) desde una pestaña clínica no
  // debe animar el subárbol. Se mide sobre el WIDGET DEL SHELL, no sobre la sección: la
  // página de la sección ya es NoTransitionPage en el navegador anidado, así que medir ahí
  // pasaría siempre sin probar nada. El shell es la página que antes animaba (MaterialPage).
  testWidgets('entrar a Administración no anima el subárbol (§12)', (t) async {
    final router = await _mount(t);
    router.go('/'); // arranca en una pestaña clínica
    await t.pumpAndSettle();
    router.go('/admin/usuarios');
    await t.pumpAndSettle();
    expect(
      ModalRoute.of(t.element(find.byType(AdminSectionsShell)))!
          .transitionDuration,
      Duration.zero,
      reason: 'entrar a Administración no debe animar el subárbol completo',
    );
  });

  testWidgets('entrar a la Consola del master no anima el subárbol (§12)', (t) async {
    final router = await _mount(t, user: _master);
    router.go('/'); // arranca en una pestaña clínica
    await t.pumpAndSettle();
    router.go('/platform/centros');
    await t.pumpAndSettle();
    expect(
      ModalRoute.of(t.element(find.byType(PlatformSectionsShell)))!
          .transitionDuration,
      Duration.zero,
      reason: 'entrar a la Consola del master no debe animar el subárbol completo',
    );
  });
}
