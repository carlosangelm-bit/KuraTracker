import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/features/admin/note_catalog_screen.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// 2b — la prueba que faltaba. router_module_gate_test lee el ÁRBOL del router, así
/// que pasa aunque nadie navegue: las 8 rutas podían ser decorativas y el CI seguir
/// verde. Esta monta Configuración bajo un GoRouter real, TOCA un tile y verifica que
/// la LOCATION del router cambió a la ruta esperada. Habría atrapado el bug #1
/// (context.push que abría la pantalla sin mover la URL).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tocar "Protocolo Kura+" mueve la location a /admin/protocolo-kura',
      (tester) async {
    tester.view.physicalSize = const Size(1300, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'cfg-nav-org';
    // Con module:admin el tile navega (sin él abriría el diálogo de compra).
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-admin',
      'organization_id': org,
      'kind': 'module',
      'key': 'admin',
      'status': 'active',
      'source': 'master',
    });

    final router = GoRouter(
      initialLocation: '/admin',
      routes: [
        GoRoute(
          path: '/admin',
          builder: (c, s) => NoteCatalogScreen(repo: repo, organizationId: org),
          routes: [
            GoRoute(
              path: 'protocolo-kura',
              builder: (c, s) =>
                  const Scaffold(body: Center(child: Text('STUB-PK'))),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    // Estamos en /admin, la pantalla destino aún no.
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/admin');
    expect(find.text('STUB-PK'), findsNothing);
    expect(find.text('Protocolo Kura+'), findsOneWidget);

    await tester.tap(find.text('Protocolo Kura+'));
    await tester.pumpAndSettle();

    // La LOCATION cambió y la pantalla destino se montó.
    expect(router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/protocolo-kura');
    expect(find.text('STUB-PK'), findsOneWidget);
  });
}
