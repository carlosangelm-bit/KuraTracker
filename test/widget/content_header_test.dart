// Prueba de CONDUCTA sobre el ROUTER REAL: en /admin y /platform el encabezado vive
// DENTRO del área de contenido (canvas "Navegación KuraTracker", tablero "Escritorio ·
// riel abierto"), NO en una barra de título por encima. A cualquier ancho:
//   (a) NO existe AppBar por encima del contenido, y
//   (b) el nombre de la sección aparece UNA sola vez en la pantalla.
// Verificación en rojo: dejar la barra reintroduce el AppBar y duplica el nombre.
//
// CI-ONLY: importar app_router arrastra todas las pantallas → google_fonts, que la
// toolchain local (3.44) no compila. `flutter analyze` sí valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/features/admin/admin_home_screen.dart';
import 'package:kuratracker/features/platform/platform_home_screen.dart';
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

void _resize(WidgetTester t, double w) {
  t.view.physicalSize = Size(w, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> _open(WidgetTester t, AppUser user, Set<ModuleKey> mods,
    String route, double w) async {
  _resize(t, w);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // --- /admin (admin del centro) -----------------------------------------
  testWidgets('/admin ANCHO: encabezado en el contenido, sin AppBar', (t) async {
    await _open(t, _admin, _adminMods, '/admin/usuarios', 1400);
    expect(find.byType(AdminSectionsShell), findsOneWidget);
    // (a) No hay barra de título por encima del contenido.
    expect(find.byType(AppBar), findsNothing);
    // (b) El título de la sección lo pinta el encabezado, una sola vez.
    expect(find.byKey(const ValueKey('content-header-title')), findsOneWidget);
  });

  testWidgets('/admin ANGOSTO: menú de sección, "Administración" una vez, sin AppBar',
      (t) async {
    await _open(t, _admin, _adminMods, '/admin/usuarios', 900);
    expect(find.byType(AppBar), findsNothing);
    // El menú Sección › Subsección ▾ vive en ESTE encabezado, no en una franja.
    expect(find.byType(KuraSectionMenu), findsOneWidget);
    // El nombre del área aparece UNA sola vez (en el menú; el riel colapsado no
    // pinta etiquetas). Dejar la barra lo pondría dos veces.
    expect(find.textContaining('Administración'), findsOneWidget);
  });

  // --- /platform (master) -------------------------------------------------
  testWidgets('/platform ANCHO: encabezado en el contenido, sin AppBar', (t) async {
    await _open(t, _master, const {}, '/platform/centros', 1400);
    expect(find.byType(PlatformSectionsShell), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('content-header-title')), findsOneWidget);
  });

  testWidgets('/platform ANGOSTO: menú de sección, "Plataforma" una vez, sin AppBar',
      (t) async {
    await _open(t, _master, const {}, '/platform/centros', 900);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(KuraSectionMenu), findsOneWidget);
    expect(find.textContaining('Plataforma'), findsOneWidget);
  });
}
