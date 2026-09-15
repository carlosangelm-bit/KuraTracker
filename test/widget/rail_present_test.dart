// §3/§10.4: la Ayuda flotante se suprime SOLO cuando hay riel (railPresentProvider). El
// cuidador no tiene riel a NINGUNA anchura, así que conserva su flotante — aquí se afirma
// del lado del PUBLICADOR: su shell nunca publica railPresent=true (si lo hiciera, TourScope
// le quitaría el flotante). El flotante en sí es de producción (AppConfig.isSupabaseConfigured,
// de compilación) y no se puede alternar en el arnés de prueba; por eso se verifica la señal
// que lo gobierna. Un clínico a ≥900 sí publica true (control positivo).
//
// CI-only: AppShell arrastra google_fonts (no compila en el toolchain local).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/section_action.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_shell.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser user) {
    state = SessionState(user: user);
  }
}

const _caregiver = AppUser(
  id: 'g1', role: AppRole.cuidador, fullName: 'Cuida Uno',
  email: 'g@x.test', staffId: 'sg1', organizationId: 'org-demo',
);
const _clin = AppUser(
  id: 'c1', role: AppRole.clinico, fullName: 'Clin Uno',
  email: 'c@x.test', staffId: 's1', organizationId: 'org-demo',
);

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(currentPath: state.matchedLocation, child: child),
          routes: [
            for (final p in const ['/', '/patients', '/agenda'])
              GoRoute(
                  path: p, builder: (_, __) => Scaffold(body: Center(child: Text(p)))),
          ],
        ),
      ],
    );

Future<bool> _railPresentFor(WidgetTester t, AppUser user, Size size) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => _FakeSession(user)),
    // Módulos suficientes para que un clínico tenga ≥2 destinos (hasNavRail). No afecta
    // al cuidador: su nav (isCaregiverOnly) es <2 destinos con o sin módulos.
    enabledModulesProvider.overrideWithValue(const {
      ModuleKey.patients,
      ModuleKey.agenda,
      ModuleKey.reports,
    }),
  ]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      routerConfig: _router(),
    ),
  ));
  await t.pump(); // corre el post-frame del publicador
  return container.read(railPresentProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const [Size(500, 900), Size(900, 900), Size(1400, 900)]) {
    testWidgets('cuidador NO tiene riel a ${size.width.toInt()}px → flotante intacto',
        (t) async {
      expect(await _railPresentFor(t, _caregiver, size), isFalse);
    });
  }

  testWidgets('clínico a 1400px SÍ tiene riel → railPresent=true (control)',
      (t) async {
    expect(await _railPresentFor(t, _clin, const Size(1400, 900)), isTrue);
  });
}
