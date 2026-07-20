// Regresión del "pantalla en blanco" / overflow del dashboard: monta el SHELL
// (una sola barra por pantalla) con el Dashboard como ruta inicial y una sesión
// falsa (modo demo), y verifica que NO se reporta ninguna excepción de
// build/layout (ni overflow). Cubre el hero, cuyo overflow no lo detectaban los
// tests previos (reports/login).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_shell.dart';
import 'package:kuratracker/features/dashboard/dashboard_screen.dart';
import 'package:kuratracker/models/app_user.dart';

class _FakeSessionController extends SessionController {
  _FakeSessionController(AppUser user) {
    state = SessionState(user: user);
  }
}

const _admin = AppUser(
  id: 'a1', role: AppRole.admin, fullName: 'Admin Uno',
  email: 'a@x.test', organizationId: 'org-demo',
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
            GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
          ],
        ),
      ],
    );

Future<void> _expectNoRenderErrors(WidgetTester t, AppUser user) async {
  final errors = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.toString());
  await t.binding.setSurfaceSize(const Size(390, 780));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
    overrides: [sessionProvider.overrideWith((ref) => _FakeSessionController(user))],
    child: MaterialApp.router(routerConfig: _router()),
  ));
  await t.pump(const Duration(milliseconds: 800));
  await t.pump(const Duration(milliseconds: 400));
  FlutterError.onError = prev;
  expect(errors, isEmpty, reason: 'Errores de render en el dashboard: $errors');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Shell + Dashboard (admin) monta sin errores de render', (t) async {
    await _expectNoRenderErrors(t, _admin);
  });

  testWidgets('Shell + Dashboard (clínico) monta sin errores de render', (t) async {
    await _expectNoRenderErrors(t, _clin);
  });
}
