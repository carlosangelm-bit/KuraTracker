import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// REJA de bradenBandLevel (lección 12-sep-2026, hecha permanente).
///
/// bradenBandLevel es un helper SÍNCRONO que lee BradenScale.cached — una caché
/// que solo se llena cuando alguien observa bradenScaleProvider (o vía la precarga
/// no-bloqueante de main). Cuando la función pasó de aritmética pura a leer esa
/// caché (6398a4d), se actualizó 1 de sus 4 llamantes; los otros tres no observaban
/// el provider, y el tablero de triage hospitalario clasificó a un paciente Braden 9
/// como "sin valoración" (Alta riesgo: 0). El CI salió VERDE en ese commit: faltaba
/// la prueba, no el disparador. Esta es esa prueba.
///
/// Falla si un archivo de lib/ LLAMA a bradenBandLevel( pero NO referencia
/// bradenScaleProvider en el mismo archivo. Un nuevo llamante que olvide observar el
/// provider rompe esta reja antes de llegar al piso.
void main() {
  test('todo archivo que llama bradenBandLevel observa bradenScaleProvider', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      // Una LLAMADA lleva paréntesis; el `import ... show bradenBandLevel;` no, así
      // que un archivo que solo reexporta el símbolo no se marca.
      if (!src.contains('bradenBandLevel(')) continue;
      if (!src.contains('bradenScaleProvider')) offenders.add(entity.path);
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Estos archivos llaman bradenBandLevel pero NO observan '
          'bradenScaleProvider; con la caché vacía clasificarían todo como "sin '
          'valoración". Agrega ref.watch(bradenScaleProvider) en su build: '
          '${offenders.join(", ")}',
    );
  });
}
