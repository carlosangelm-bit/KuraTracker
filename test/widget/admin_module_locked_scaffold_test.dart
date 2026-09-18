import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/widgets/kura_module_lock.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// 2b: la SEGUNDA capa del candado. Las 5 pantallas gateadas, al abrirse sin el
/// módulo (p. ej. tecleando la URL), rinden adminModuleLockedScaffold con el precio
/// de billing_catalog. Aquí se fija el helper compartido que todas usan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sin module:admin: rinde el bloqueo con precio (\$1,200) y el título',
      (tester) async {
    final repo = await DataRepository.instance(); // billing_catalog sembrado
    const org = 'gate-sin-admin'; // sin ningún derecho → sin module:admin

    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: Builder(
        builder: (ctx) => adminModuleLockedScaffold(
          ctx,
          repo: repo,
          organizationId: org,
          title: 'Protocolo Kura+',
          description: 'Arma los pasos de tu propio protocolo.',
        ),
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Protocolo Kura+'), findsOneWidget); // AppBar
    expect(find.text('Agregar por \$1,200 al mes'), findsOneWidget);
  });

  testWidgets('con module:admin: la sección no rinde el CTA de compra',
      (tester) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'gate-con-admin';
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-admin',
      'organization_id': org,
      'kind': 'module',
      'key': 'admin',
      'status': 'active',
      'source': 'master',
    });

    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: Builder(
        builder: (ctx) => adminModuleLockedScaffold(
          ctx,
          repo: repo,
          organizationId: org,
          title: 'Protocolo Kura+',
          description: 'Arma los pasos de tu propio protocolo.',
        ),
      ),
    )));
    await tester.pumpAndSettle();

    // Con el módulo, KuraModuleLock.section se desvanece → no hay CTA de compra.
    expect(find.text('Agregar por \$1,200 al mes'), findsNothing);
  });
}
