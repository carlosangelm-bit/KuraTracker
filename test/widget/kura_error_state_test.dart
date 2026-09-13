import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/widgets/kura_error_state.dart';

import 'kura_test_helpers.dart';

void main() {
  testWidgets('el texto de la excepción NO se muestra hasta desplegar el detalle',
      (tester) async {
    var retried = 0;
    await pumpBrand(
      tester,
      KuraErrorState(
        title: 'No pudimos cargar el inventario',
        reassurance: 'Puede ser tu conexión. Tus datos están a salvo.',
        detail: 'Exception: SocketException: failed host lookup',
        onRetry: () => retried++,
      ),
    );

    // El mensaje humano y Reintentar sí; la excepción cruda NO.
    expect(find.text('No pudimos cargar el inventario'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);

    // Desplegar el detalle revela la excepción.
    await tester.tap(find.text('Ver detalle técnico'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SocketException'), findsOneWidget);

    // Reintentar dispara el callback.
    await tester.tap(find.text('Reintentar'));
    expect(retried, 1);
  });
}
