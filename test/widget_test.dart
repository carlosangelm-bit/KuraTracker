// Test de humo basico. Los tests relevantes del dominio clinico estan en
// test/engine/ (motor Protocolo Kura+: paridad, casos limite, reglas de
// seguridad). Este archivo solo verifica que la app arranca sin excepciones.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kuratracker/main.dart';

void main() {
  testWidgets('La app arranca y muestra la pantalla de login', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: KuraTrackerApp()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('KuraTracker'), findsWidgets);
  });
}
