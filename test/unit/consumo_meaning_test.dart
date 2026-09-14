import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/features/insumos/consumo_meaning.dart';

/// La cifra "Consumo del mes" del Inventario NUNCA va sola: su línea de
/// significado SIEMPRE compara contra el mes anterior (acuerdo del canvas). Este
/// test fija esa regla — que un rediseño no la reduzca a "solo el número del mes".
void main() {
  group('consumoMeaning', () {
    test('baja: signo menos tipográfico y mes anterior nombrado', () {
      // 92 vs 100 → −8%.
      expect(
        consumoMeaning(current: 92, prev: 100, prevLabel: 'agosto'),
        '−8% contra agosto',
      );
    });

    test('subida: signo más', () {
      expect(
        consumoMeaning(current: 120, prev: 100, prevLabel: 'agosto'),
        '+20% contra agosto',
      );
    });

    test('igual: +0% (sigue comparando, no se calla)', () {
      expect(
        consumoMeaning(current: 100, prev: 100, prevLabel: 'julio'),
        '+0% contra julio',
      );
    });

    test('sin mes anterior pero con consumo: lo dice, no divide entre cero', () {
      expect(
        consumoMeaning(current: 30, prev: 0, prevLabel: 'agosto'),
        'sin agosto para comparar',
      );
    });

    test('sin consumo en ninguno de los dos meses', () {
      expect(
        consumoMeaning(current: 0, prev: 0, prevLabel: 'agosto'),
        'sin salidas registradas este mes',
      );
    });

    test('la comparación NUNCA es solo la cifra del mes en curso', () {
      // Cualquiera que sea el caso con prev>0, la línea menciona el mes anterior.
      final line = consumoMeaning(current: 5, prev: 8, prevLabel: 'marzo');
      expect(line.contains('marzo'), isTrue);
      expect(line.contains('%'), isTrue);
    });
  });

  group('spanishMonth', () {
    test('mapea 1..12 a nombres en español', () {
      expect(spanishMonth(1), 'enero');
      expect(spanishMonth(8), 'agosto');
      expect(spanishMonth(12), 'diciembre');
    });
  });
}
