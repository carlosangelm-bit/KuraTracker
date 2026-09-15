// § Admin del centro — cierre (Configuración y Marca). NoteCatalogTab y BrandingTab
// salieron de admin_home_screen.dart a note_catalog_screen.dart (NoteCatalogScreen) y
// branding_screen.dart (BrandingScreen), con BrandTokens. Son CUERPOS de sección:
// AdminSectionsShell aporta el ÚNICO KuraContentHeader y el ÚNICO KuraAccountMenu.
//
// Pruebas de conducta, cada una roja antes:
//  1. /admin/configuracion monta NoteCatalogScreen; un solo header y un solo menú de
//     cuenta a 1200 px.
//  2. /admin/marca monta BrandingScreen (con module:admin); un solo header y un solo
//     menú de cuenta a 1200 px.
//  3. Con sesión de hospital (tema azul) y SIN color de marca guardado, el color
//     PROPUESTO en Marca es el azul del hospital (0xFF2563EB), no el violeta fijo
//     (0xFF7C3AED). Es el arreglo del respaldo `_parse(...) ?? brandPrimary` + no
//     sembrar el violeta por defecto.
//
// CI-ONLY: importar app_router / las pantallas arrastra google_fonts (no compila en la
// toolchain local 3.44). `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart' show KuraContentHeader;
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/router/app_shell.dart' show KuraAccountMenu;
import 'package:kuratracker/features/admin/branding_screen.dart' show BrandingScreen;
import 'package:kuratracker/features/admin/note_catalog_screen.dart'
    show NoteCatalogScreen;
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

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
};

Future<void> _open(WidgetTester t, String route, double w) async {
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
    ),
  ));
  await t.pumpAndSettle();
  router.go(route);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('/admin/configuracion monta NoteCatalogScreen, un solo header/cuenta',
      (t) async {
    await _open(t, '/admin/configuracion', 1200);
    expect(find.byType(NoteCatalogScreen), findsOneWidget,
        reason: 'la ruta debe montar NoteCatalogScreen, no NoteCatalogTab');
    expect(find.byType(KuraContentHeader), findsOneWidget);
    expect(find.byType(KuraAccountMenu), findsOneWidget);
  });

  testWidgets('/admin/marca monta BrandingScreen, un solo header/cuenta', (t) async {
    // Marca está gateada por module:admin (premiumAdminFor); se siembra para que
    // renderice BrandingScreen y no el candado.
    final store = await LocalStore.instance();
    await store.upsert(Collections.orgEntitlements, {
      'id': 'org-demo-admin',
      'organization_id': 'org-demo',
      'kind': 'module',
      'key': 'admin',
      'status': 'active',
      'source': 'master',
    });
    await _open(t, '/admin/marca', 1200);
    expect(find.byType(BrandingScreen), findsOneWidget,
        reason: 'la ruta debe montar BrandingScreen, no BrandingTab');
    expect(find.byType(KuraContentHeader), findsOneWidget);
    expect(find.byType(KuraAccountMenu), findsOneWidget);
  });

  testWidgets('hospital sin color guardado: el color propuesto es azul, no violeta',
      (t) async {
    final repo = await DataRepository.instance();
    // Tema del HOSPITAL + sin color de marca guardado (organizationId sin fila).
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(
          extensions: <ThemeExtension<dynamic>>[BrandTokens.hospital]),
      home: Scaffold(
        body: BrandingScreen(repo: repo, organizationId: null),
      ),
    ));
    await t.pumpAndSettle();

    // El color propuesto pinta la vista previa del encabezado del reporte.
    final preview = t.widget<Text>(find.text('Reporte de herida'));
    expect(preview.style?.color, const Color(0xFF2563EB),
        reason: 'debe proponer el azul del hospital (su propia marca)');
    expect(preview.style?.color, isNot(const Color(0xFF7C3AED)),
        reason: 'no el violeta fijo de la clínica');
  });
}
