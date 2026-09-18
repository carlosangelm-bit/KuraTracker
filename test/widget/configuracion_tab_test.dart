import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/features/admin/note_catalog_screen.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Humo de la etapa 2a: la pestaña Configuración (NoteCatalogScreen) rinde sus tres
/// grupos sin excepción de build/layout, y el encabezado del canvas está presente.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('los tres grupos rinden sin overflow', (tester) async {
    tester.view.physicalSize = const Size(1440, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = await DataRepository.instance();
    final org = repo.listOrganizations().first.id;

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
        home: Scaffold(body: NoteCatalogScreen(repo: repo, organizationId: org)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Configuración del centro'), findsOneWidget);
    expect(find.text('Catálogo de la nota de seguimiento'), findsOneWidget);
    expect(find.text('Tu propio protocolo'), findsOneWidget);
    expect(find.text('Expediente y cumplimiento'), findsOneWidget);
    expect(find.text('Siempre incluido'), findsOneWidget);
    // La barra de acciones del grupo 1 y su primaria.
    expect(find.text('Nuevo concepto'), findsOneWidget);
    expect(find.text('Herramientas'), findsOneWidget);
  });
}
