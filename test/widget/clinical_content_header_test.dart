// § etapa 5 (simetría b) — Encabezado. Las pantallas clínicas de primer nivel llevan el
// encabezado DENTRO del contenido (KuraContentHeader vía KuraPageHeader), igual que
// /admin y /platform: NO hay AppBar por encima del contenido, y el nombre de la pantalla
// aparece UNA sola vez (la llave 'content-header-title'). Misma prueba que content_header.
//
// Además: la cuenta (cerrar sesión / cambiar de centro) vive en el pie del riel en
// ESCRITORIO —no se duplica un UserMenuButton en el encabezado— y en MÓVIL (sin riel)
// SÍ aparece en el encabezado, para no perder el acceso.
//
// Rojo verificado devolviendo una pantalla a `appBar: AppBar(...)`: reaparece el AppBar.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la
// toolchain local (3.44) no compila. `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/router/app_shell.dart' show UserMenuButton;
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
  ModuleKey.prevention,
  ModuleKey.vac,
  ModuleKey.insumos,
  ModuleKey.comercial,
};

// Rutas clínicas de PRIMER NIVEL con pantalla propia (encabezado en contenido).
const _routes = ['/patients', '/reports', '/risk', '/vac', '/agenda', '/insumos'];

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

  testWidgets('cada clínica de primer nivel: sin AppBar, título una sola vez', (t) async {
    for (final route in _routes) {
      await _open(t, route, 1400);
      expect(find.byType(AppBar), findsNothing,
          reason: '$route: no debe haber AppBar por encima del contenido');
      expect(find.byKey(const ValueKey('content-header-title')), findsOneWidget,
          reason: '$route: el nombre de la pantalla va una sola vez, en el encabezado');
    }
  });

  testWidgets('escritorio: la cuenta NO se duplica en el encabezado (vive en el riel)',
      (t) async {
    await _open(t, '/reports', 1400);
    expect(find.byType(AppBar), findsNothing);
    // En escritorio la cuenta está en el pie del riel (KuraAccountMenu), no como
    // UserMenuButton en el encabezado.
    expect(find.byType(UserMenuButton), findsNothing,
        reason: 'no debe duplicarse la cuenta en el encabezado de escritorio');
  });

  testWidgets('móvil: sin AppBar, con la cuenta en el encabezado (no hay riel)',
      (t) async {
    await _open(t, '/reports', 800);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('content-header-title')), findsOneWidget);
    // Sin riel, la cuenta va en el encabezado para conservar el acceso a cerrar sesión.
    expect(find.byType(UserMenuButton), findsOneWidget,
        reason: 'en móvil la cuenta debe estar en el encabezado');
  });
}
