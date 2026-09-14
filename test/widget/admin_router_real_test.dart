// Prueba de INVOCACIÓN contra el ROUTER REAL (no una réplica): la réplica es justo
// lo que dejó pasar el bug de que /admin/<sección> terminaba en /admin/usuarios.
// Recorre el routerProvider real navegando a cada una de las seis secciones y exige
// que (a) el location final sea esa ruta y (b) la pantalla montada sea la de esa
// sección (su entrada del riel queda marcada como activa, derivada de widget.section).
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

const _sections = ['usuarios', 'personal', 'sitios', 'configuracion', 'marca', 'licencias'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('las seis /admin/<sección> resuelven a su ruta y montan su sección',
      (t) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final repo = await DataRepository.instance();
    final container = ProviderContainer(overrides: [
      sessionProvider.overrideWith((ref) => _FakeSessionController(_admin)),
      dataRepositoryProvider.overrideWith((ref) => repo),
      enabledModulesProvider.overrideWithValue(const {
        ModuleKey.patients,
        ModuleKey.agenda,
        ModuleKey.reports,
      }),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider); // EL ROUTER REAL
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
        routerConfig: router,
      ),
    ));
    await t.pumpAndSettle();

    for (final s in _sections) {
      router.go('/admin/$s');
      await t.pumpAndSettle();
      // (a) el location final es la ruta tecleada (no /admin/usuarios).
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/$s',
        reason: 'navegar a /admin/$s no terminó ahí',
      );
      // (b) la pantalla montada es la de esa sección: su entrada del riel (derivada de
      //     widget.section) queda marcada como activa.
      expect(
        find.byKey(ValueKey('nav-active:/admin/$s')),
        findsOneWidget,
        reason: 'la sección montada no es $s',
      );
    }
  });
}
