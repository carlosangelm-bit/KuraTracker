// /platform/centros monta la vista NUEVA (PlatformCentersView) y, a 1200 px, hay UN solo
// KuraContentHeader y UN solo KuraAccountMenu (el cromo lo da PlatformSectionsShell).
//
// CI-ONLY: importar app_router arrastra google_fonts (no compila en la toolchain local
// 3.44). `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart' show KuraContentHeader;
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/router/app_shell.dart' show KuraAccountMenu;
import 'package:kuratracker/features/platform/centers_view.dart' show PlatformCentersView;
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser user) {
    state = SessionState(user: user);
  }
}

const _master = AppUser(
  id: 'm1',
  role: AppRole.master,
  fullName: 'Master Uno',
  email: 'm@x.test',
);

Future<void> _open(WidgetTester t, double w) async {
  t.view.physicalSize = Size(w, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  final repo = await DataRepository.instance();
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => _FakeSession(_master)),
    dataRepositoryProvider.overrideWith((ref) => repo),
    enabledModulesProvider.overrideWithValue(const <ModuleKey>{}),
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
  router.go('/platform/centros');
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('/platform/centros monta la vista nueva, un solo header/cuenta a 1200',
      (t) async {
    await _open(t, 1200);
    expect(find.byType(PlatformCentersView), findsOneWidget,
        reason: 'la ruta debe montar PlatformCentersView (la vista de derechos)');
    expect(find.byType(KuraContentHeader), findsOneWidget);
    expect(find.byType(KuraAccountMenu), findsOneWidget);
  });
}
