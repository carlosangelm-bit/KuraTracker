// § Admin del centro — Etapa 1 (Usuarios). `UsersTab` salió de admin_home_screen.dart a
// lib/features/admin/users_screen.dart, renombrada `UsersScreen`, con BrandTokens en vez
// de KuraColors (el alias morado fijo que hacía que estas pantallas salieran moradas en
// un hospital). Es un CUERPO de sección: AdminSectionsShell aporta el ÚNICO
// KuraContentHeader («Administración › Usuarios») y el ÚNICO KuraNavRail (cuenta en el
// pie). Envolverla en KuraScreen daría un segundo encabezado — la familia de defecto que
// ya costó dos rieles y dos menús de cuenta.
//
// Pruebas de INVOCACIÓN (router real) + una de escaneo de fuente, cada una roja antes:
//  1. /admin/usuarios monta UsersScreen (el tipo nuevo).
//  2. A 1200px: un solo KuraContentHeader y un solo KuraAccountMenu en el árbol.
//  3. users_screen.dart no contiene la cadena 'KuraColors'.
//
// CI-ONLY (las de router real): importar app_router arrastra google_fonts (no compila en
// la toolchain local 3.44). `flutter analyze` valida; corre en CI (3.27.1).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart' show KuraContentHeader;
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/router/app_shell.dart' show KuraAccountMenu;
import 'package:kuratracker/features/admin/users_screen.dart' show UsersScreen;
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

const _mods = <ModuleKey>{
  ModuleKey.patients,
  ModuleKey.agenda,
  ModuleKey.reports,
};

Future<void> _open(WidgetTester t, String route, double w) async {
  t.view.physicalSize = Size(w, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  final repo = await DataRepository.instance();
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => _FakeSession(_admin)),
    dataRepositoryProvider.overrideWith((ref) => repo),
    enabledModulesProvider.overrideWithValue(_mods),
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('/admin/usuarios monta UsersScreen (el tipo nuevo)', (t) async {
    await _open(t, '/admin/usuarios', 1200);
    expect(find.byType(UsersScreen), findsOneWidget,
        reason: 'la ruta debe montar UsersScreen, no UsersTab');
  });

  testWidgets('a 1200px: un solo encabezado y un solo menú de cuenta', (t) async {
    await _open(t, '/admin/usuarios', 1200);
    // El encabezado lo pinta AdminSectionsShell, una sola vez. Si Usuarios trajera su
    // propio KuraScreen (→ KuraPageHeader → KuraContentHeader.flat), habría dos.
    expect(find.byType(KuraContentHeader), findsOneWidget,
        reason: 'un solo encabezado en la pantalla');
    // La cuenta vive solo en el pie del riel.
    expect(find.byType(KuraAccountMenu), findsOneWidget,
        reason: 'un solo menú de cuenta en la pantalla');
  });

  test('users_screen.dart no contiene la cadena KuraColors', () {
    final src =
        File('lib/features/admin/users_screen.dart').readAsStringSync();
    expect(src.contains('KuraColors'), isFalse,
        reason: 'la paleta debe salir de BrandTokens, no del alias fijo KuraColors');
  });
}
