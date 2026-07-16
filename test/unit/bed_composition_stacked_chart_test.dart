import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/features/follow_up/follow_up_screen.dart';
import 'package:kuratracker/models/wound.dart';

/// Pruebas de la logica pura de normalizacion/acumulacion usada por el
/// grafico de lineas 100% apiladas de composicion del lecho (feat:
/// tissue-composition-stacked-chart). No se testea el widget/fl_chart en
/// si (no hay convencion de tests de pintura de grafico en este proyecto),
/// sino la funcion [bedCompositionCumulative] que garantiza que la ultima
/// suma acumulada sea siempre 100 (o 0 si no hay dato), sin importar si
/// los 4 porcentajes capturados originalmente suman exactamente 100.
void main() {
  WoundMeasurement measurement({
    required double granulation,
    required double slough,
    required double necrosis,
    required double epithelialization,
  }) {
    return WoundMeasurement(
      id: 'm1',
      woundId: 'w1',
      measuredAt: DateTime(2026, 1, 1),
      lengthCm: 1,
      widthCm: 1,
      areaCm2: 1,
      granulationPct: granulation,
      sloughPct: slough,
      necrosisPct: necrosis,
      epithelializationPct: epithelialization,
    );
  }

  group('bedCompositionCumulative', () {
    test('suma acumulada final es 100 cuando los 4 porcentajes ya suman 100', () {
      final m = measurement(granulation: 70, slough: 20, necrosis: 5, epithelialization: 5);
      final c = bedCompositionCumulative(m);
      expect(c.length, 4);
      expect(c[0], closeTo(70, 0.001));
      expect(c[1], closeTo(90, 0.001));
      expect(c[2], closeTo(95, 0.001));
      expect(c[3], closeTo(100, 0.001));
    });

    test('normaliza a 100 cuando la captura original NO suma 100 (dato imperfecto)', () {
      // 40 + 40 + 40 + 40 = 160 (suma imperfecta, sin validacion en captura)
      final m = measurement(granulation: 40, slough: 40, necrosis: 40, epithelialization: 40);
      final c = bedCompositionCumulative(m);
      // Cada componente normalizado es 25% (40/160*100), asi que la
      // suma acumulada avanza en pasos iguales de 25 hasta llegar a 100.
      expect(c[0], closeTo(25, 0.001));
      expect(c[1], closeTo(50, 0.001));
      expect(c[2], closeTo(75, 0.001));
      expect(c[3], closeTo(100, 0.001));
    });

    test('normaliza a 100 cuando la suma original es menor a 100 (dato incompleto parcial)', () {
      // 10 + 10 + 0 + 0 = 20
      final m = measurement(granulation: 10, slough: 10, necrosis: 0, epithelialization: 0);
      final c = bedCompositionCumulative(m);
      expect(c[0], closeTo(50, 0.001)); // 10/20*100
      expect(c[1], closeTo(100, 0.001)); // (10+10)/20*100
      expect(c[2], closeTo(100, 0.001));
      expect(c[3], closeTo(100, 0.001));
    });

    test('devuelve [0,0,0,0] sin dividir por cero cuando la suma original es 0', () {
      final m = measurement(granulation: 0, slough: 0, necrosis: 0, epithelialization: 0);
      final c = bedCompositionCumulative(m);
      expect(c, [0.0, 0.0, 0.0, 0.0]);
    });

    test('cada suma acumulada es monotona no-decreciente (garantiza franjas validas)', () {
      final m = measurement(granulation: 33, slough: 12, necrosis: 8, epithelialization: 47);
      final c = bedCompositionCumulative(m);
      expect(c[0], lessThanOrEqualTo(c[1]));
      expect(c[1], lessThanOrEqualTo(c[2]));
      expect(c[2], lessThanOrEqualTo(c[3]));
      expect(c[3], closeTo(100, 0.001));
    });
  });
}
