import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/features/platform/derechos/module_agreement.dart';

/// Corrección (c): el motivo se muestra como línea COMPLETA, sin ellipsis — la fila
/// crece para mostrarlo entero, nunca se trunca. Conducta: el Text no fija maxLines
/// ni overflow ellipsis y muestra todo el contenido.
void main() {
  const largo =
      '"Cortesía extendida para el centro piloto del norte mientras se cierra el '
      'acuerdo comercial anual con la dirección médica"';

  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
        home: Scaffold(body: SizedBox(width: 200, child: child)),
      );

  testWidgets('el motivo se pinta completo, sin ellipsis ni maxLines', (tester) async {
    await tester.pumpWidget(host(const ModuleReasonText(largo)));
    await tester.pumpAndSettle();

    expect(find.text(largo), findsOneWidget);
    final w = tester.widget<Text>(find.text(largo));
    expect(w.maxLines, isNull); // no se limita a N líneas
    expect(w.overflow, isNot(TextOverflow.ellipsis)); // no se trunca con …
  });
}
