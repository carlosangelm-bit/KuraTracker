// § Admin del centro — Etapa 2 (Personal). `StaffTab` salió de admin_home_screen.dart a
// lib/features/admin/staff_screen.dart, renombrada `StaffScreen`, con BrandTokens en vez
// de KuraColors. Es un CUERPO de sección: AdminSectionsShell aporta el ÚNICO
// KuraContentHeader («Administración › Personal») y el ÚNICO KuraNavRail (cuenta en el
// pie); envolverla en KuraScreen daría un segundo encabezado.
//
// Pruebas de conducta, cada una roja antes:
//  1. /admin/personal monta StaffScreen (el tipo nuevo).          [router real, CI-only]
//  2. A 1200px: un solo KuraContentHeader y un solo KuraAccountMenu. [router real, CI-only]
//  3. El avatar usa las INICIALES del nombre, no el folio: «Ana Ruiz» → "A", no "20"
//     (dos caracteres del folio, iguales para todo el personal del año); y un folio
//     vacío NO lanza RangeError (la regresión que tumbó la pantalla del master). [local]
//  4. staff_screen.dart no contiene la cadena 'KuraColors'.                        [local]
//
// CI-ONLY (las de router real): importar app_router arrastra google_fonts (no compila en
// la toolchain local 3.44). `flutter analyze` valida; corren en CI (3.27.1). Las 3 y 4 no
// tocan el router y corren en local.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart' show KuraContentHeader;
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/core/router/app_shell.dart' show KuraAccountMenu;
import 'package:kuratracker/features/admin/staff_screen.dart' show StaffScreen;
import 'package:kuratracker/features/admin/staff_avatar.dart' show StaffAvatar;
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/models/staff.dart';
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
};

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: Scaffold(body: Center(child: child)),
    );

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

  testWidgets('/admin/personal monta StaffScreen (el tipo nuevo)', (t) async {
    await _open(t, '/admin/personal', 1200);
    expect(find.byType(StaffScreen), findsOneWidget,
        reason: 'la ruta debe montar StaffScreen, no StaffTab');
  });

  testWidgets('a 1200px: un solo encabezado y un solo menú de cuenta', (t) async {
    await _open(t, '/admin/personal', 1200);
    expect(find.byType(KuraContentHeader), findsOneWidget,
        reason: 'un solo encabezado en la pantalla');
    expect(find.byType(KuraAccountMenu), findsOneWidget,
        reason: 'un solo menú de cuenta en la pantalla');
  });

  testWidgets('el avatar usa iniciales del nombre, no los dígitos del folio',
      (t) async {
    final ana = StaffMember(
        id: 's1',
        folio: 'K2026-0001',
        fullName: 'Ana Ruiz',
        createdAt: DateTime(2026));
    await t.pumpWidget(_wrap(StaffAvatar(member: ana)));
    // Con la corrección: inicial del nombre.
    expect(find.text('A'), findsOneWidget);
    // Con el código de hoy (folio.substring(1, 3)) saldría "20" para todo el personal.
    expect(find.text('20'), findsNothing,
        reason: 'el avatar no debe repetir los dígitos del año del folio');
  });

  testWidgets('un folio vacío no lanza RangeError (regresión que tumbó la pantalla)',
      (t) async {
    final sinFolio = StaffMember(
        id: 's2', folio: '', fullName: 'Beto Sosa', createdAt: DateTime(2026));
    await t.pumpWidget(_wrap(StaffAvatar(member: sinFolio)));
    expect(t.takeException(), isNull,
        reason: 'substring sin protección sobre un folio vacío tiraba la pantalla');
    expect(find.text('B'), findsOneWidget);
  });

  test('staff_screen.dart no contiene la cadena KuraColors', () {
    final src =
        File('lib/features/admin/staff_screen.dart').readAsStringSync();
    expect(src.contains('KuraColors'), isFalse,
        reason: 'la paleta debe salir de BrandTokens, no del alias fijo KuraColors');
  });
}
