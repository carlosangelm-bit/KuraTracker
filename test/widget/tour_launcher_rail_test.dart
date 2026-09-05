// Regresión (escritorio, ≥900px, NavigationRail): el lanzador flotante del Tour
// NO debe empalmarse con el rail ni robarle toques. Esta clase de bug ya mordió
// dos veces (candado /admin, inicial del avatar): un guard estructural.
//
// El anclaje viejo `left: 88` caía ENCIMA del NavigationRail (que en español
// mide ~140px), así que un toque en la zona baja del rail podía pegarle al
// lanzador. Aquí se monta el shell real + TourScope a 1200×800 y se afirma:
//   1. el rect del lanzador NO intersecta el rect del rail;
//   2. tocar cada destino del rail navega y deja el tour en running == false;
//   3. tocar espacio vacío del rail tampoco arranca el tour.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/router/app_shell.dart';
import 'package:kuratracker/features/tour/tour_controller.dart';
import 'package:kuratracker/features/tour/tour_scope.dart';
import 'package:kuratracker/models/app_user.dart';

class _FakeSessionController extends SessionController {
  _FakeSessionController(AppUser user) {
    state = SessionState(user: user);
  }
}

const _clin = AppUser(
  id: 'c1', role: AppRole.clinico, fullName: 'Clin Uno',
  email: 'c@x.test', staffId: 's1', organizationId: 'org-demo',
);

const _railPaths = [
  '/', '/patients', '/agenda', '/prevention-agenda',
  '/vac', '/reports', '/insumos', '/comercial', '/admin',
];

GoRouter _buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(currentPath: state.matchedLocation, child: child),
          routes: [
            for (final p in _railPaths)
              GoRoute(path: p, builder: (_, __) => Scaffold(body: Center(child: Text(p)))),
          ],
        ),
      ],
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('escritorio: el lanzador del Tour no se empalma con el rail ni le roba toques',
      (t) async {
    SharedPreferences.setMockInitialValues({}); // deja auto-start la primera vez
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    final router = _buildRouter();
    final container = ProviderContainer(overrides: [
      sessionProvider.overrideWith((ref) => _FakeSessionController(_clin)),
      routerProvider.overrideWithValue(router),
    ]);
    addTearDown(container.dispose);

    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (c, child) =>
            TourScope(child: child ?? const SizedBox.shrink()),
      ),
    ));
    await _settle(t);

    // Cerrar el recorrido de auto-inicio ("Saltar"): así se muestra el lanzador.
    container.read(tourProvider.notifier).stop();
    await _settle(t);

    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget, reason: 'a 1200px debe haber NavigationRail');
    final launcher = find.byIcon(Icons.play_circle_outline);
    expect(launcher, findsOneWidget, reason: 'el lanzador del Tour debe mostrarse tras Saltar');

    // 1. El lanzador (con su padding táctil de 11px) no intersecta el rail.
    final railRect = t.getRect(rail);
    final launcherRect = t.getRect(launcher).inflate(11);
    expect(railRect.overlaps(launcherRect), isFalse,
        reason: 'el lanzador ($launcherRect) se empalma con el rail ($railRect)');

    // 2. Tocar cada destino del rail navega y NO arranca el tour.
    for (final lbl in const ['Reportes', 'Pacientes', 'Comercial', 'Inicio']) {
      final f = find.text(lbl);
      if (f.evaluate().isEmpty) continue;
      await t.tap(f.first, warnIfMissed: false);
      await _settle(t);
      expect(container.read(tourProvider).running, isFalse,
          reason: 'tocar "$lbl" en el rail arrancó el tour');
      container.read(tourProvider.notifier).stop();
      await _settle(t);
    }

    // 3. Tocar espacio vacío del rail tampoco arranca el tour.
    await t.tapAt(const Offset(40, 620));
    await _settle(t);
    expect(container.read(tourProvider).running, isFalse,
        reason: 'tocar espacio vacío del rail arrancó el tour');
  });
}
