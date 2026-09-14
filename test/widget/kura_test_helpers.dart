import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';

/// Monta un widget bajo un MaterialApp con los tokens de la marca dada, para que
/// `BrandTokens.of(context)` resuelva hospital/cuidadores/kura en las pruebas.
Future<void> pumpBrand(
  WidgetTester tester,
  Widget child, {
  BrandTokens tokens = BrandTokens.kura,
  double width = 900,
  double height = 1400,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[tokens]),
      home: Scaffold(body: child),
    ),
  );
}

/// Recolecta TODOS los colores resueltos en el árbol (texto, íconos, superficies,
/// bordes, Material). Sirve para atrapar un `KuraColors` olvidado: si algo pintó el
/// morado de marca a mano, aparece aquí aunque el tema sea hospital.
Set<Color> collectColors(WidgetTester tester) {
  final colors = <Color>{};
  for (final w in tester.allWidgets) {
    if (w is Text) {
      final c = w.style?.color;
      if (c != null) colors.add(c);
    } else if (w is Icon) {
      final c = w.color;
      if (c != null) colors.add(c);
    } else if (w is Material) {
      final c = w.color;
      if (c != null) colors.add(c);
    } else if (w is ColoredBox) {
      colors.add(w.color);
    } else if (w is DecoratedBox) {
      final d = w.decoration;
      if (d is BoxDecoration) {
        if (d.color != null) colors.add(d.color!);
        final b = d.border;
        if (b is Border) {
          colors.add(b.top.color);
        }
      }
    }
  }
  return colors;
}
