// Dos arreglos post-merge (vivían en producción, main @ 3edefa3):
//  1. El tablero (Inicio) armaba su propio encabezado con un UserMenuButton
//     INCONDICIONAL. A ≥900px el riel ya muestra la cuenta en su pie → DOS menús de
//     cuenta idénticos en Inicio (banda de riel abierto y colapsada). El tablero pasa a
//     condicionar la cuenta con hasNavRail (la MISMA fuente que KuraPageHeader y
//     AppShell.showRail), no una copia del ancho.
//  2. El lanzador de Ayuda usaba bottom:84 fijo y no sabía del FAB, que se ELEVA su
//     huella (kFloatingNavBarHeight+12) incluso en escritorio. En Inicio a 1400 tapaba
//     «Nuevo paciente». Ahora libera esa huella derivándola de las mismas constantes.
//
// Pruebas de INVOCACIÓN sobre el router real, cada una verificada en ROJO:
//  - Admin de clínica a 1200px en Inicio: KuraAccountMenu aparece UNA sola vez.
//  - Pantalla con KuraPrimaryFab (VAC) a ancho de escritorio: el lanzador de ayuda y el
//    FAB no se traslapan.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la
// toolchain local (3.44) no compila. `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/router/app_shell.dart' show KuraAccountMenu;
import 'package:kuratracker/features/tour/tour_controller.dart';
import 'package:kuratracker/features/tour/tour_scope.dart';
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
  ModuleKey.vac,
};

Future<(GoRouter, ProviderContainer)> _mount(WidgetTester t,
    {required double w, bool tour = false}) async {
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
      builder: tour
          ? (ctx, child) => TourScope(child: child ?? const SizedBox.shrink())
          : null,
    ),
  ));
  await t.pumpAndSettle();
  return (router, container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Inicio a 1200px (admin clínica): la cuenta aparece una sola vez',
      (t) async {
    final (router, _) = await _mount(t, w: 1200);
    router.go('/');
    await t.pumpAndSettle();
    // Hay riel (ancho ≥900 y ≥2 destinos): la cuenta vive en su pie.
    expect(find.byType(KuraNavRail), findsOneWidget);
    // Un SOLO menú de cuenta en Inicio: el del riel. El tablero ya no lo duplica.
    expect(find.byType(KuraAccountMenu), findsOneWidget,
        reason: 'la cuenta no debe duplicarse en Inicio cuando hay riel');
  });

  testWidgets('pantalla con KuraPrimaryFab a 1400px: lanzador y FAB no se traslapan',
      (t) async {
    final (router, container) = await _mount(t, w: 1400, tour: true);
    router.go('/vac');
    // Asentado manual: el overlay del tour anima y pumpAndSettle podría no converger.
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    // Cerrar el auto-inicio del tour para que aparezca el lanzador flotante.
    container.read(tourProvider.notifier).stop();
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }

    final launcher = find.byIcon(Icons.play_circle_outline);
    final fab = find.byType(FloatingActionButton);
    expect(launcher, findsOneWidget,
        reason: 'debe verse el lanzador tras cerrar el tour');
    expect(fab, findsOneWidget, reason: 'la pantalla VAC trae KuraPrimaryFab');

    // El lanzador (con su área táctil de 11px) NO debe intersectar el FAB.
    final launcherRect = t.getRect(launcher).inflate(11);
    final fabRect = t.getRect(fab);
    expect(fabRect.overlaps(launcherRect), isFalse,
        reason: 'el lanzador ($launcherRect) se traslapa con el FAB ($fabRect)');
  });
}
