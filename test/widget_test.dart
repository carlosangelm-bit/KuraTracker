// Test de humo basico. Los tests relevantes del dominio clinico estan en
// test/engine/ (motor Protocolo Kura+: paridad, casos limite, reglas de
// seguridad). Este archivo solo verifica que la app arranca sin excepciones.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/main.dart';

void main() {
  testWidgets('La app arranca y muestra la landing de la demo',
      (WidgetTester tester) async {
    // La landing /demo es un gate async (FutureBuilder sobre hasLead): sin lead
    // capturado muestra el formulario de captura, que también rotula
    // "KuraTracker". Se mockean las prefs para que el futuro resuelva.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: KuraTrackerApp()));
    // Un pump arranca el futuro; el segundo deja que resuelva y reconstruya al
    // formulario (que ya no tiene animación en reposo).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('KuraTracker'), findsWidgets);
  });
}
