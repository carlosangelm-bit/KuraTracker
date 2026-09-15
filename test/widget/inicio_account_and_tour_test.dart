// Dos arreglos post-merge (vivían en producción, main @ 3edefa3):
//  1. El tablero (Inicio) armaba su propio encabezado con un UserMenuButton
//     INCONDICIONAL. A ≥900px el riel ya muestra la cuenta en su pie → DOS menús de
//     cuenta idénticos en Inicio (banda de riel abierto y colapsada). El tablero pasa a
//     condicionar la cuenta con hasNavRail (la MISMA fuente que KuraPageHeader y
//     AppShell.showRail), no una copia del ancho.
//  2. El lanzador de Ayuda usaba bottom:84 fijo y no sabía del FAB. Esa colisión ya no
//     existe: tras «la acción sale de los flotantes» (§3), CON riel la acción de la
//     pantalla vive en el ENCABEZADO (botón sólido), no en un FAB — así no hay nada
//     flotante sobre el contenido que el lanzador pueda tapar en escritorio.
//
// Pruebas de INVOCACIÓN sobre el router real, cada una verificada en ROJO:
//  - Admin de clínica a 1200px en Inicio: KuraAccountMenu aparece UNA sola vez.
//  - VAC a ancho de escritorio (riel): la acción está en el encabezado, sin FAB flotante;
//    el lanzador del Tour (demo) se mantiene.
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
import 'package:kuratracker/core/nav/section_action.dart' show SectionActionButton;
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

  testWidgets(
      'VAC a 1400px (riel): la acción está en el encabezado, sin FAB flotante que tape',
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

    // El lanzador del Tour (demo) SIGUE flotando: lo que se muda al riel es la Ayuda de
    // producción, no el Tour.
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget,
        reason: 'el lanzador del Tour se mantiene en la demo');
    // §3: con riel la acción de VAC sube al encabezado (botón sólido) y NO hay FAB — así
    // ya no hay nada flotante sobre el contenido que el lanzador pueda tapar.
    expect(find.byType(FloatingActionButton), findsNothing,
        reason: 'con riel la acción de VAC vive en el encabezado, no en un FAB');
    expect(find.byType(SectionActionButton), findsOneWidget,
        reason: 'la acción de VAC está en el encabezado');
  });
}
