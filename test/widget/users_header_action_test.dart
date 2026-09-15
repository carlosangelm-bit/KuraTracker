// §3/§5: a ≥900 px la acción principal de Usuarios («Nuevo usuario») sale del FAB
// flotante y sube al ENCABEZADO como botón sólido; a <900 se queda como FAB (zona del
// pulgar). Sobre el ROUTER REAL, en dos anchuras.
//
// CI-ONLY: importar app_router / UsersScreen arrastra google_fonts (no compila en la
// toolchain local 3.44). `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/section_action.dart' show SectionActionButton;
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/widgets/kura_primary_fab.dart' show KuraPrimaryFab;
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

Future<void> _open(WidgetTester t, double w) async {
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
  router.go('/admin/usuarios');
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a 1400 px la acción va al encabezado y NO hay FAB', (t) async {
    await _open(t, 1400);
    expect(find.byType(SectionActionButton), findsOneWidget,
        reason: 'a ≥900 px la acción principal es un botón del encabezado');
    expect(find.byType(KuraPrimaryFab), findsNothing,
        reason: 'a ≥900 px no debe montarse el FAB flotante');
  });

  testWidgets('a 430 px se queda el FAB y no hay botón en el encabezado', (t) async {
    await _open(t, 430);
    expect(find.byType(KuraPrimaryFab), findsOneWidget,
        reason: 'a <900 px el FAB se queda en la zona del pulgar');
    expect(find.byType(SectionActionButton), findsNothing,
        reason: 'a <900 px la acción no va al encabezado');
  });
}
