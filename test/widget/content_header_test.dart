// Prueba de CONDUCTA sobre el ROUTER REAL: en /admin y /platform el encabezado vive
// DENTRO del área de contenido (canvas "Navegación KuraTracker", tablero "Escritorio ·
// riel abierto"), NO en una barra de título por encima. Por eso, a cualquier ancho:
//   (a) NO existe AppBar por encima del contenido, y
//   (b) el nombre de la sección aparece UNA sola vez en la pantalla.
// Verificación en rojo: dejar la barra superior (AppBar) hace que el nombre salga dos
// veces (barra + encabezado) y reaparece el AppBar → ambas aserciones fallan.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la
// toolchain local (3.44) no compila. `flutter analyze` sí valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:go_router/go_router.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
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

Future<GoRouter> _mount(
  WidgetTester t,
  AppUser user,
  Set<ModuleKey> modules,
) async {
  final repo = await DataRepository.instance();
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => _FakeSessionController(user)),
    dataRepositoryProvider.overrideWith((ref) => repo),
    enabledModulesProvider.overrideWithValue(modules),
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
  return router;
}

void _resize(WidgetTester t, double w) {
  t.view.physicalSize = Size(w, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Cada caso: (etiqueta, usuario, módulos, ruta de sección, nombre del área).
  final cases = <List<Object>>[
    ['/admin', _admin, <ModuleKey>{ModuleKey.patients, ModuleKey.agenda, ModuleKey.reports}, '/admin/usuarios', 'Administración'],
    ['/platform', _master, <ModuleKey>{}, '/platform/centros', 'Plataforma'],
  ];

  for (final c in cases) {
    final label = c[0] as String;
    final user = c[1] as AppUser;
    final modules = c[2] as Set<ModuleKey>;
    final route = c[3] as String;
    final area = c[4] as String;

    testWidgets('$label ANCHO: encabezado en el contenido, sin AppBar', (t) async {
      _resize(t, 1400); // riel abierto → miga estática (padre + título)
      final router = await _mount(t, user, modules);
      router.go(route);
      await t.pumpAndSettle();

      // (a) No hay barra de título por encima del contenido.
      expect(find.byType(AppBar), findsNothing,
          reason: '$label ancho: quedó un AppBar por encima del contenido');
      // (b) El título de la sección lo pinta el encabezado del contenido, una vez.
      expect(find.byKey(const ValueKey('content-header-title')), findsOneWidget,
          reason: '$label ancho: el título del encabezado no aparece una sola vez');
    });

    testWidgets('$label ANGOSTO: menú Sección › Subsección, sin AppBar', (t) async {
      _resize(t, 900); // riel colapsado (solo iconos) → encabezado con el menú
      final router = await _mount(t, user, modules);
      router.go(route);
      await t.pumpAndSettle();

      // (a) Tampoco hay AppBar en angosto.
      expect(find.byType(AppBar), findsNothing,
          reason: '$label angosto: quedó un AppBar por encima del contenido');
      // El menú Sección › Subsección ▾ vive en ESTE encabezado, no en una franja.
      expect(find.byType(KuraSectionMenu), findsOneWidget,
          reason: '$label angosto: falta el menú de sección en el encabezado');
      // (b) El nombre del área aparece UNA sola vez (en el menú; el riel colapsado
      //     no pinta etiquetas). Dejar la barra lo pondría dos veces.
      expect(find.textContaining(area), findsOneWidget,
          reason: '$label angosto: "$area" no aparece exactamente una vez');
    });
  }
}
