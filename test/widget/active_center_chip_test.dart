// #5 — el centro activo se MUESTRA (no modo invisible). El chip (y el migajón, que
// leen la MISMA fuente, activeOrganizationIdProvider) nombran el centro que consultó
// la puerta. Master: aparece con el nombre del centro ACTIVO (el seleccionado, no el
// de origen). No-master: NO aparece (activo == origen; conducta idéntica).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/providers/active_organization_provider.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_shell.dart' show ActiveCenterChip;
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser user) {
    state = SessionState(user: user);
  }
}

AppUser _user(AppRole role, String org) => AppUser(
      id: 'u-${role.name}', role: role, fullName: 'X', email: 'x@y.test',
      organizationId: org,
    );

Future<void> _pump(WidgetTester t, DataRepository repo, AppUser user,
    {String? override}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      sessionProvider.overrideWith((ref) => _FakeSession(user)),
      dataRepositoryProvider.overrideWith((ref) => repo),
      activeOrgOverrideProvider
          .overrideWith((ref) => ActiveOrgOverride.withValue(override)),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: const Scaffold(body: ActiveCenterChip()),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('MASTER: el chip nombra el centro ACTIVO (seleccionado), no el de origen',
      (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    await store.upsert(Collections.organizations,
        {'id': 'org-home', 'name': 'Kura+', 'center_type': 'clinica_heridas'});
    await store.upsert(Collections.organizations, {
      'id': 'org-activo', 'name': 'Prueba Fase 2', 'center_type': 'clinica_heridas'
    });
    await _pump(t, repo, _user(AppRole.master, 'org-home'), override: 'org-activo');
    expect(find.text('Centro activo: Prueba Fase 2'), findsOneWidget);
    expect(find.textContaining('Kura+'), findsNothing);
  });

  testWidgets('NO-MASTER: el chip NO aparece (activo == origen, idéntico)', (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    await store.upsert(Collections.organizations,
        {'id': 'org-home', 'name': 'Kura+', 'center_type': 'clinica_heridas'});
    // Aun con una anulación residual, el no-master no la aplica ni pinta chip.
    await _pump(t, repo, _user(AppRole.admin, 'org-home'), override: 'org-activo');
    expect(find.byType(ActiveCenterChip), findsOneWidget);
    expect(find.textContaining('Centro activo'), findsNothing);
  });
}
