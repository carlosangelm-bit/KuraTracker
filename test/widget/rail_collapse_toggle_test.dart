// Prueba de CONDUCTA sobre el ROUTER REAL: pulsar el chevron del riel CAMBIA el
// estado del riel (abierto ⇄ colapsado) en /admin y /platform. Es la prueba que
// FALTABA: hasta hoy solo se verificaba que el estado colapsado se PINTA bien
// (content_header_test), ninguna que el BOTÓN lo dispare — por eso el cableado de
// onToggleCollapse se rompió dos veces (al subir el riel a un ShellRoute y al mover
// el encabezado al contenido) sin que nada avisara.
//
// Por qué el ROUTER REAL y no KuraNavRail aislado: el defecto vive en el CABLEADO del
// shell (AdminSectionsShell/PlatformSectionsShell pasan onToggleCollapse al riel). Un
// test del riel aislado cablea su propio callback y pasaría aunque el shell lo dejara
// de pasar — no habría atrapado ninguna de las dos roturas. Esta prueba monta el shell
// real por el router, así que si el shell deja de pasar el callback, el tap no hace
// nada y la prueba se pone ROJA.
//
// Verificación en rojo (hecha desconectando el callback): poner `onToggleCollapse: null`
// en AdminSectionsShell/PlatformSectionsShell deja el chevron inerte → tras el tap sigue
// 'Colapsar' y 'Expandir' nunca aparece → esta prueba falla. Es exactamente la regresión
// reportada ("el botón de colapsar volvió a quedar inerte tras mover el encabezado").
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

Future<void> _open(WidgetTester t, AppUser user, Set<ModuleKey> mods,
    String route, double w) async {
  t.view.physicalSize = Size(w, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

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
  router.go(route);
  await t.pumpAndSettle();
}

/// El riel arranca ABIERTO a ≥1200 px: existe 'Colapsar' (chevron_left) y NO 'Expandir'.
void _expectOpen(String where) {
  expect(find.byTooltip('Colapsar'), findsOneWidget,
      reason: '$where: el riel abierto debe ofrecer el botón Colapsar');
  expect(find.byTooltip('Expandir'), findsNothing,
      reason: '$where: abierto no debe haber botón Expandir');
}

/// Colapsado: aparece 'Expandir' (chevron_right) y desaparece 'Colapsar'.
void _expectCollapsed(String where) {
  expect(find.byTooltip('Expandir'), findsOneWidget,
      reason: '$where: tras pulsar Colapsar el riel debe ofrecer Expandir');
  expect(find.byTooltip('Colapsar'), findsNothing,
      reason: '$where: colapsado ya no debe haber botón Colapsar');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('/admin: pulsar el chevron colapsa y expande el riel', (t) async {
    await _open(t, _admin, _adminMods, '/admin/usuarios', 1400);
    _expectOpen('/admin');

    // Pulsar Colapsar → el riel pasa a colapsado (lo dispara onToggleCollapse del shell).
    await t.tap(find.byTooltip('Colapsar'));
    await t.pumpAndSettle();
    _expectCollapsed('/admin');

    // Y de vuelta: pulsar Expandir → abierto otra vez (el toggle va en ambos sentidos).
    await t.tap(find.byTooltip('Expandir'));
    await t.pumpAndSettle();
    _expectOpen('/admin tras expandir');
  });

  testWidgets('/platform: pulsar el chevron colapsa y expande el riel', (t) async {
    await _open(t, _master, const {}, '/platform/centros', 1400);
    _expectOpen('/platform');

    await t.tap(find.byTooltip('Colapsar'));
    await t.pumpAndSettle();
    _expectCollapsed('/platform');

    await t.tap(find.byTooltip('Expandir'));
    await t.pumpAndSettle();
    _expectOpen('/platform tras expandir');
  });
}
