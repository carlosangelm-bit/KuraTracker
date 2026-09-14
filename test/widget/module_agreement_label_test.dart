import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/features/platform/derechos/module_agreement.dart';

/// Prueba 5 (§6), parte de RENDER: el caso "encendido sin derecho" debe mostrarse
/// con SU texto y en ROJO (statusDanger, desde BrandTokens). Es la razón de ser del
/// rediseño; sin este render el caso silencioso vuelve a no verse. Borrar la rama
/// onWithoutRight de moduleAgreement pone esta prueba (y la unitaria) en rojo.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
        home: Scaffold(body: child),
      );

  testWidgets('encendido sin derecho → texto rojo exacto', (tester) async {
    await tester.pumpWidget(host(
      ModuleAgreementLabel(moduleAgreement(hasRight: false, switchOn: true)),
    ));
    await tester.pumpAndSettle();

    final finder = find.text('Encendido en el centro, pero sin derecho: nadie lo ve.');
    expect(finder, findsOneWidget);
    final textWidget = tester.widget<Text>(finder);
    expect(textWidget.style?.color, BrandTokens.kura.statusDanger);
  });

  testWidgets('los otros tres casos NO usan el rojo de peligro', (tester) async {
    for (final a in [
      moduleAgreement(hasRight: true, switchOn: true),
      moduleAgreement(hasRight: true, switchOn: false),
      moduleAgreement(hasRight: false, switchOn: false),
    ]) {
      await tester.pumpWidget(host(ModuleAgreementLabel(a)));
      await tester.pumpAndSettle();
      final tw = tester.widget<Text>(find.text(a.message));
      expect(tw.style?.color, isNot(BrandTokens.kura.statusDanger));
    }
  });
}
