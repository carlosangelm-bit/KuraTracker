// §15 etapa 6.2 — los TRES estados de la Matriz, cada uno con su render. 364 líneas de pantalla no
// pueden quedar sin prueba: autora → catálogo con cabecera; admin sin autoría → editor propio
// (delegado); sin permiso → mensaje dicho, no vacío. El candado comercial (sin module:admin) lo
// cubre admin_gated_screens_lock_test; aquí todos los orgs traen el módulo para llegar al gating por rol.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/features/admin/protocol_matrix_screen.dart';
import 'package:kuratracker/features/admin/protocol_product_rules_screen.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

class _FakeSessionController extends SessionController {
  _FakeSessionController(AppUser user) {
    state = SessionState(user: user);
  }
}

AppUser _user(AppRole role, String org) => AppUser(
      id: 'u-${role.name}',
      role: role,
      fullName: 'X',
      email: 'x@y.test',
      organizationId: org,
    );

Future<void> _seedEntitlement(
    LocalStore store, String org, String key) async {
  await store.upsert(Collections.orgEntitlements, {
    'id': '$org-$key',
    'organization_id': org,
    'kind': 'module',
    'key': key,
    'status': 'active',
    'source': 'master',
  });
}

Future<void> _pump(
    WidgetTester t, DataRepository repo, AppUser user, String org) async {
  t.view.physicalSize = const Size(1200, 2200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ProviderScope(
    overrides: [
      sessionProvider.overrideWith((ref) => _FakeSessionController(user)),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: ProtocolMatrixScreen(repo: repo, organizationId: org),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('AUTORA (admin + protocol:author) → catálogo con cabecera del régimen',
      (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'matrix-author';
    await _seedEntitlement(store, org, 'admin'); // pasa el candado comercial
    await _seedEntitlement(store, org, 'protocol:author'); // autoría
    await _pump(t, repo, _user(AppRole.admin, org), org);
    // La cabecera del interruptor (el guion de la presentación) siempre está en modo catálogo.
    expect(find.text('Este centro resuelve el protocolo con:'), findsOneWidget);
    expect(find.byType(ProtocolProductRulesScreen), findsNothing);
  });

  testWidgets('admin SIN autoría → editor de reglas propias (delegado)', (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'matrix-own';
    await _seedEntitlement(store, org, 'admin'); // módulo sí; protocol:author NO
    await _pump(t, repo, _user(AppRole.admin, org), org);
    // Se delega al editor existente (para no perder la edición de reglas propias).
    expect(find.byType(ProtocolProductRulesScreen), findsOneWidget);
    expect(find.text('Este centro resuelve el protocolo con:'), findsNothing);
  });

  testWidgets('sin permiso (no admin) → se DICE, no se deja en blanco', (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'matrix-noperm';
    await _seedEntitlement(store, org, 'admin');
    await _pump(t, repo, _user(AppRole.clinico, org), org);
    expect(find.textContaining('No tienes permiso'), findsOneWidget);
    expect(find.byType(ProtocolProductRulesScreen), findsNothing);
  });
}
