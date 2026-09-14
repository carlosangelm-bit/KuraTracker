// § etapa 5 — La cuenta (cerrar sesión / cambiar de centro) debe estar SIEMPRE alcanzable.
// KuraPageHeader añade la cuenta al encabezado cuando NO hay riel, y "no hay riel" se
// deriva de la declaración única (kuraNavDestinations): riel = ancho Y ≥2 destinos
// visibles. La condición vieja ("es angosto") dejaba al CUIDADOR —un solo destino, sin
// riel ni en ancho— sin cuenta en ningún lado: regresión de la etapa 5.
//
// Pruebas de INVOCACIÓN sobre el router real (no del helper):
//  1. Cuidador a 1200px: UserMenuButton presente en el encabezado (no hay riel).
//  2. Clínica (admin de hospital) a 1200px: UserMenuButton AUSENTE del encabezado y la
//     cuenta presente en el pie del riel (un solo menú de cuenta, sin duplicar).
// Rojo verificado volviendo la condición a `if (!wide)`: el cuidador a 1200px se queda
// sin UserMenuButton.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la
// toolchain local (3.44) no compila. `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/router/app_shell.dart'
    show UserMenuButton, KuraAccountMenu;
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/center_type.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser user, CenterType centerType) {
    state = SessionState(user: user, activeCenterType: centerType);
  }
}

const _caregiver = AppUser(
  id: 'c1',
  role: AppRole.cuidador,
  fullName: 'Cuidador Uno',
  email: 'c@x.test',
  organizationId: 'org-demo',
);

const _admin = AppUser(
  id: 'a1',
  role: AppRole.admin,
  fullName: 'Admin Uno',
  email: 'a@x.test',
  organizationId: 'org-demo',
  staffId: 's1',
);

Future<void> _open(WidgetTester t, AppUser user, Set<ModuleKey> mods, String route,
    {CenterType centerType = CenterType.clinicaHeridas}) async {
  t.view.physicalSize = const Size(1200, 1000); // ancho: habría riel si hay ≥2 destinos
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  final repo = await DataRepository.instance();
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => _FakeSession(user, centerType)),
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cuidador a 1200px: la cuenta va en el encabezado (no hay riel)',
      (t) async {
    await _open(t, _caregiver, const {}, '/caregiver');
    // Un solo destino → sin riel aun en ancho.
    expect(find.byType(KuraNavRail), findsNothing,
        reason: 'el cuidador tiene un solo destino: no hay riel');
    // La cuenta DEBE seguir alcanzable, en el encabezado.
    expect(find.byType(UserMenuButton), findsOneWidget,
        reason: 'sin riel, la cuenta del cuidador va en el encabezado');
  });

  testWidgets('admin de hospital a 1200px: cuenta en el pie del riel, no duplicada',
      (t) async {
    await _open(t, _admin, const {
      ModuleKey.patients,
      ModuleKey.prevention,
      ModuleKey.reports,
    }, '/patients', centerType: CenterType.hospital);
    // Con ≥2 destinos y en ancho, el riel existe.
    expect(find.byType(KuraNavRail), findsOneWidget);
    // La cuenta NO se duplica en el encabezado…
    expect(find.byType(UserMenuButton), findsNothing,
        reason: 'con riel, el encabezado no debe repetir la cuenta');
    // …y vive en el pie del riel: EXACTAMENTE un menú de cuenta en la pantalla.
    expect(find.byType(KuraAccountMenu), findsOneWidget,
        reason: 'la cuenta debe estar (una vez) en el pie del riel');
  });
}
