// §13.1 — Las hijas PROFUNDAS de /admin (protocolo, productos, tipos de cita/consulta,
// depurar, escalas, fuente de recomendaciones, divulgaciones) se abren con `context.go`
// (reemplaza la ubicación) y viven FUERA del shell de secciones → Navigator.canPop es false,
// el AppBar no pinta flecha y no hay salida salvo el botón del navegador. El arreglo: un
// KuraBackButton explícito como `leading:`, con fallback a su punto de entrada (Configuración).
//
// La lista de rutas se ENUMERA desde la configuración REAL del router (no a mano): una novena
// pantalla profunda queda cubierta el día que se declare. Para cada una: monta un
// KuraBackButton y, al tocarlo (sin nada que desapilar, como al entrar por URL), la ubicación
// queda en /admin/configuracion.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la toolchain
// local (3.44) no compila. `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/widgets/kura_back_button.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser user) {
    state = SessionState(user: user);
  }
}

const _admin = AppUser(
  id: 'a1', role: AppRole.admin, fullName: 'Admin Uno',
  email: 'a@x.test', organizationId: 'org-demo', staffId: 's1',
);

// Las SEIS secciones (dentro del shell de secciones) NO son pantallas profundas.
const _sectionPaths = {
  '/admin/usuarios',
  '/admin/personal',
  '/admin/sitios',
  '/admin/configuracion',
  '/admin/marca',
  '/admin/licencias',
};

/// Recorre la config REAL del router y junta toda GoRoute cuyo path empieza con '/admin/'
/// y no es una de las seis secciones: las hijas profundas.
Iterable<String> _deepAdminPaths(List<RouteBase> routes) sync* {
  for (final r in routes) {
    if (r is GoRoute) {
      if (r.path.startsWith('/admin/') && !_sectionPaths.contains(r.path)) {
        yield r.path;
      }
      yield* _deepAdminPaths(r.routes);
    } else {
      yield* _deepAdminPaths(r.routes);
    }
  }
}

Future<GoRouter> _mount(WidgetTester t) async {
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final repo = await DataRepository.instance();
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => _FakeSession(_admin)),
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
  await _settle(t);
  return router;
}

/// Asentado por cuadros fijos, NO pumpAndSettle: algunas hijas (Acuity) disparan un Future
/// de red en initState que podría no converger. El AppBar (con el KuraBackButton) se pinta
/// en el primer cuadro, así que basta.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cada hija profunda de /admin trae KuraBackButton → /admin/configuracion',
      (t) async {
    final router = await _mount(t);
    final deep = _deepAdminPaths(router.configuration.routes).toSet().toList();

    // Enumeración real: hoy son ocho; el >= deja crecer sin reescribir la prueba.
    expect(deep.length, greaterThanOrEqualTo(8),
        reason: 'se esperaban ≥8 hijas profundas de /admin; salieron $deep');

    for (final path in deep) {
      router.go(path);
      await _settle(t);
      expect(find.byType(KuraBackButton), findsOneWidget,
          reason: '$path no monta KuraBackButton');
      await t.tap(find.byType(KuraBackButton));
      await _settle(t);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/configuracion',
        reason: 'volver desde $path no cayó en /admin/configuracion',
      );
    }
  });
}
