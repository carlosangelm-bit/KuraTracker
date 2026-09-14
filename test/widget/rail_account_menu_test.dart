// Prueba de CONDUCTA sobre el ROUTER REAL: al quitar el AppBar de /admin y /platform
// se fue el UserMenuButton — el único acceso a cerrar sesión. El PIE del riel debe ser
// ahora el menú de cuenta: identidad = control. Desde /admin y /platform existe un
// control ALCANZABLE que dispara el cierre de sesión (abierto y colapsado).
// Verificación en rojo: dejar el pie inerte (sin accountMenuBuilder) → no hay control
// que abrir, 'Cerrar sesión' no existe y el logout nunca se dispara.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la
// toolchain local (3.44) no compila. `flutter analyze` sí valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/router/app_shell.dart' show KuraAccountMenu;
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Espía: registra que se pidió cerrar sesión y limpia la sesión (sin tocar Supabase).
class _SpySessionController extends SessionController {
  bool loggedOut = false;
  _SpySessionController(AppUser user) {
    state = SessionState(user: user);
  }
  @override
  Future<void> logout() async {
    loggedOut = true;
    state = const SessionState();
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

Future<_SpySessionController> _mount(WidgetTester t, AppUser user,
    Set<ModuleKey> mods, String route, double w) async {
  t.view.physicalSize = Size(w, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  final spy = _SpySessionController(user);
  final repo = await DataRepository.instance();
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => spy),
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
  router.go(route);
  await t.pumpAndSettle();
  return spy;
}

Future<void> _tapLogout(WidgetTester t, _SpySessionController spy) async {
  // El control del pie del riel (abierto o colapsado) abre el menú de cuenta.
  expect(find.byType(KuraAccountMenu), findsOneWidget,
      reason: 'no hay control de cuenta alcanzable en el pie del riel');
  await t.tap(find.byType(KuraAccountMenu));
  await t.pumpAndSettle();
  expect(find.text('Cerrar sesión'), findsOneWidget,
      reason: 'el menú de cuenta no ofrece Cerrar sesión');
  await t.tap(find.text('Cerrar sesión'));
  await t.pumpAndSettle();
  expect(spy.loggedOut, isTrue, reason: 'el control no disparó el cierre de sesión');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('/admin ANCHO: el pie del riel cierra sesión', (t) async {
    final spy = await _mount(t, _admin, _adminMods, '/admin/usuarios', 1400);
    await _tapLogout(t, spy);
  });

  testWidgets('/admin COLAPSADO: el avatar del pie cierra sesión', (t) async {
    final spy = await _mount(t, _admin, _adminMods, '/admin/usuarios', 900);
    await _tapLogout(t, spy);
  });

  testWidgets('/platform ANCHO: el pie del riel cierra sesión', (t) async {
    final spy = await _mount(t, _master, const {}, '/platform/centros', 1400);
    await _tapLogout(t, spy);
  });
}
