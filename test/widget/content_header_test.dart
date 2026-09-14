// Prueba de CONDUCTA sobre el ROUTER REAL: en /admin y /platform el encabezado vive
// DENTRO del área de contenido (canvas "Navegación KuraTracker", tablero "Escritorio ·
// riel abierto"), NO en una barra de título por encima. A cualquier ancho: no existe
// AppBar por encima del contenido y el nombre de la sección aparece una sola vez.
// Verificación en rojo: dejar la barra reintroduce el AppBar y duplica el nombre.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la
// toolchain local (3.44) no compila. `flutter analyze` sí valida; corre en CI (3.27.1).
//
// Los casos de /platform están ATOMIZADOS (una aserción por prueba) para poder ubicar
// un fallo por el conteo cuando los logs de CI no son legibles: si falla el alcance del
// shell, caen todas; si no, cae solo la aserción del encabezado afectada.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:go_router/go_router.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/features/admin/admin_home_screen.dart';
import 'package:kuratracker/features/platform/platform_home_screen.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';

class _FakeSessionController extends SessionController {
  _FakeSessionController(AppUser user) {
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

const _master = AppUser(
  id: 'm1',
  role: AppRole.master,
  fullName: 'Master Uno',
  email: 'm@x.test',
);

const _adminMods = <ModuleKey>{
  ModuleKey.patients,
  ModuleKey.agenda,
  ModuleKey.reports,
};

void _resize(WidgetTester t, double w) {
  t.view.physicalSize = Size(w, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<GoRouter> _mount(WidgetTester t, AppUser user, Set<ModuleKey> mods) async {
  final repo = await DataRepository.instance();
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => _FakeSessionController(user)),
    dataRepositoryProvider.overrideWith((ref) => repo),
    enabledModulesProvider.overrideWithValue(mods),
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

Future<void> _open(WidgetTester t, AppUser user, Set<ModuleKey> mods,
    String route, double w) async {
  _resize(t, w);
  final router = await _mount(t, user, mods);
  router.go(route);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ------------------------------------------------------------------ /admin
  testWidgets('/admin ANCHO: encabezado en el contenido, sin AppBar', (t) async {
    await _open(t, _admin, _adminMods, '/admin/usuarios', 1400);
    expect(find.byType(AdminSectionsShell), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('content-header-title')), findsOneWidget);
  });

  testWidgets('/admin ANGOSTO: menú de sección, área una vez, sin AppBar', (t) async {
    await _open(t, _admin, _adminMods, '/admin/usuarios', 900);
    expect(find.byType(AdminSectionsShell), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(KuraSectionMenu), findsOneWidget);
    expect(find.textContaining('Administración'), findsOneWidget);
  });

  // --------------------------------------------------------------- /platform
  // Atómicas: aíslan alcance del shell vs. cada aserción del encabezado.
  testWidgets('/platform C1 ANCHO: el master alcanza el shell', (t) async {
    await _open(t, _master, const {}, '/platform/centros', 1400);
    expect(find.byType(PlatformSectionsShell), findsOneWidget);
  });

  testWidgets('/platform C2 ANCHO: sin AppBar', (t) async {
    await _open(t, _master, const {}, '/platform/centros', 1400);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('/platform C3 ANCHO: título del encabezado una vez', (t) async {
    await _open(t, _master, const {}, '/platform/centros', 1400);
    expect(find.byKey(const ValueKey('content-header-title')), findsOneWidget);
  });

  testWidgets('/platform D1 ANGOSTO: sin AppBar', (t) async {
    await _open(t, _master, const {}, '/platform/centros', 900);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('/platform D2 ANGOSTO: menú de sección', (t) async {
    await _open(t, _master, const {}, '/platform/centros', 900);
    expect(find.byType(KuraSectionMenu), findsOneWidget);
  });

  testWidgets('/platform D3 ANGOSTO: "Plataforma" una vez', (t) async {
    await _open(t, _master, const {}, '/platform/centros', 900);
    expect(find.textContaining('Plataforma'), findsOneWidget);
  });
}
