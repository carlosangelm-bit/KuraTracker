// §5 / §8.1 / §10.6: el botón de la acción en el encabezado es SÓLIDO con su rótulo
// completo, y cuando la acción está CANDADO (Sitios sin módulo Administración) muestra el
// candado y —al tocarlo— abre la venta, no queda muerto. Local: section_action solo usa
// BrandTokens/material.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/section_action.dart';

Widget _host(SectionAction a) => MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: Scaffold(body: Center(child: SectionActionButton(a))),
    );

void main() {
  testWidgets('acción normal: muestra su ícono y rótulo completo, y acciona', (t) async {
    var taps = 0;
    await t.pumpWidget(_host(SectionAction(
      sectionKey: 'sitios',
      label: 'Nuevo',
      icon: Icons.add_location_alt_outlined,
      onPressed: () => taps++,
    )));
    expect(find.text('Nuevo'), findsOneWidget);
    expect(find.byIcon(Icons.add_location_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    await t.tap(find.byType(SectionActionButton));
    expect(taps, 1);
  });

  testWidgets('acción CANDADO (§8.1): muestra el candado y abre la venta al tocar',
      (t) async {
    var upsell = 0;
    await t.pumpWidget(_host(SectionAction(
      sectionKey: 'sitios',
      label: 'Nuevo',
      icon: Icons.add_location_alt_outlined,
      locked: true,
      onPressed: () => upsell++,
    )));
    // El candado sustituye al ícono de la acción; el rótulo se conserva.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.add_location_alt_outlined), findsNothing);
    expect(find.text('Nuevo'), findsOneWidget);
    await t.tap(find.byType(SectionActionButton));
    expect(upsell, 1, reason: 'el candado abre la venta, no es un botón muerto');
  });
}
