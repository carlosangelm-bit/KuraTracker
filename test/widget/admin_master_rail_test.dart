// §13.3 — Un MASTER que entra a Administración no debe perder su riel: AdminSectionsShell
// construía los destinos con `isMaster: false` CLAVADO, así que el master perdía el destino
// Plataforma (y ganaba Inicio) —un riel distinto del que traía—. El arreglo toma el rol de
// la sesión. Aquí: con sesión MASTER en /admin/usuarios, el riel CONTIENE '/platform'.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la toolchain
// local (3.44) no compila. `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/nav/nav_destination.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser user) {
    state = SessionState(user: user);
  }
}

const _master = AppUser(
  id: 'm1', role: AppRole.master, fullName: 'Master Uno',
  email: 'm@x.test', organizationId: 'org-demo', staffId: 's9',
);

Future<GoRouter> _mount(WidgetTester t, AppUser user) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('el master conserva Plataforma en el riel de Administración', (t) async {
    final router = await _mount(t, _master);
    router.go('/admin/usuarios');
    await t.pumpAndSettle();

    final rail = t.widget<KuraNavRail>(find.byType(KuraNavRail));
    final routes = navFlattenVisible(rail.destinations).map((d) => d.route).toSet();
    expect(routes, contains('/platform'),
        reason: 'el master pierde Plataforma al entrar a Administración (isMaster clavado)');
  });
}
