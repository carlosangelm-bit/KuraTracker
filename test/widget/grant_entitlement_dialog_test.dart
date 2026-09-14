import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/features/platform/derechos/grant_entitlement_dialog.dart';

/// Pruebas 6 y 7 (§6), de conducta, sobre el diálogo Otorgar derecho (§5.3). El
/// diálogo no toca el repo (recibe los objetivos y un onSubmit), así corre en local.
void main() {
  const target = GrantTarget(
    kind: 'module',
    key: 'insumos',
    label: 'Insumos',
    monthlyCents: 120000,
  );

  Widget host() => MaterialApp(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
        home: Scaffold(
          body: GrantEntitlementDialog(
            targets: const [target],
            onSubmit: ({
              required target,
              required grantType,
              required reason,
              quantity,
              until,
              required permanent,
            }) async {},
          ),
        ),
      );

  bool otorgarEnabled(WidgetTester tester) {
    final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Otorgar'));
    return btn.onPressed != null;
  }

  testWidgets('6 · Otorgar deshabilitado con motivo corto, habilitado al completarlo',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Nada elegido → deshabilitado.
    expect(otorgarEnabled(tester), isFalse);

    // Tipo + vigencia (Permanente) puestos, pero sin motivo → sigue deshabilitado.
    await tester.tap(find.text('Cortesía'));
    await tester.pump();
    await tester.tap(find.byType(Checkbox)); // Permanente
    await tester.pump();
    expect(otorgarEnabled(tester), isFalse);

    // Motivo corto (<10) → deshabilitado.
    await tester.enterText(find.byType(TextField), 'corto');
    await tester.pump();
    expect(otorgarEnabled(tester), isFalse);

    // Motivo suficiente (≥10) → habilitado.
    await tester.enterText(find.byType(TextField), 'razón suficientemente larga');
    await tester.pump();
    expect(otorgarEnabled(tester), isTrue);
  });

  // La fecha solo se PINTA con !permanent, así que ambas facetas (vaciar y
  // deshabilitar) se observan DESMARCANDO Permanente después: si el estado quedó
  // limpio, al desmarcar no reaparece fecha.

  testWidgets('7a · "Permanente" VACÍA la fecha (no la conserva escondida)',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Fecha elegida → se ve el vencimiento y el total del periodo.
    await tester.tap(find.text('30 días'));
    await tester.pump();
    expect(find.textContaining('Vence el'), findsOneWidget);
    expect(find.textContaining('Total del periodo'), findsOneWidget);

    // Marcar Permanente → desaparece el total (y la fecha se pinta solo con !permanent).
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.textContaining('Total del periodo'), findsNothing);

    // Desmarcar: si Permanente VACIÓ la fecha, no reaparece.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.textContaining('Vence el'), findsNothing);
  });

  testWidgets('7b · "Permanente" DESHABILITA la fecha (los presets no fijan)',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Marcar Permanente primero.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    // Intentar fijar una fecha con un preset (deshabilitado) → no debe fijar.
    await tester.tap(find.text('30 días'));
    await tester.pump();
    // Desmarcar: si el preset estaba deshabilitado, no quedó fecha.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.textContaining('Vence el'), findsNothing);
  });
}
