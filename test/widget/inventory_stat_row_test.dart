import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/features/insumos/inventory_stat_row.dart';

/// Prueba de INVOCACIÓN de "Consumo del mes": los tests unitarios fijan la función
/// pura (consumoMeaning), pero no que el Inventario la LLAME y RENDERICE. Esta monta
/// la fila real de cifras y exige que, con current=120 y prev=100, el render traiga
/// la cifra y la comparación "+20% contra agosto".
///
/// Criterio de aceptación de conducta: si alguien quita el `meaning:` del KuraStat de
/// consumo en InventoryStatRow, esta prueba se pone en ROJO (verificado a mano).
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(
            extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
        home: Scaffold(
          body: SizedBox(width: 1200, child: child),
        ),
      );

  testWidgets('la fila renderiza la cifra de consumo con su comparación',
      (tester) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(const InventoryStatRow(
      articleCount: 48,
      reorderCount: 7,
      outCount: 2,
      valueCents: 1234500,
      consumoCurrent: 120,
      consumoPrev: 100,
      prevMonthLabel: 'agosto',
    )));
    await tester.pumpAndSettle();

    // La cifra del mes en curso.
    expect(find.text('120'), findsOneWidget);
    // Y su línea de comparación contra el mes anterior (la invocación real).
    expect(find.textContaining('+20% contra agosto'), findsOneWidget);
    // La etiqueta de la cifra existe (es de verdad "Consumo del mes").
    expect(find.text('Consumo del mes'), findsOneWidget);
  });

  testWidgets('una bajada sale con el signo menos tipográfico', (tester) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(const InventoryStatRow(
      articleCount: 10,
      reorderCount: 0,
      outCount: 0,
      valueCents: 0,
      consumoCurrent: 92,
      consumoPrev: 100,
      prevMonthLabel: 'agosto',
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('−8% contra agosto'), findsOneWidget);
  });
}
