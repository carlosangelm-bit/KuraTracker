import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tints.dart';
import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/widgets/kura_stat.dart';

import 'kura_test_helpers.dart';

void main() {
  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  testWidgets('normal: los tres textos usan la jerarquía de texto habitual',
      (tester) async {
    await pumpBrand(
      tester,
      const KuraStat(
          label: 'Valor', value: '38,420', meaning: 'a costo'),
    );
    const t = BrandTokens.kura;
    expect(colorOf(tester, 'Valor'), t.textSecondary);
    expect(colorOf(tester, '38,420'), t.textPrimary);
    expect(colorOf(tester, 'a costo'), t.textDisabled);
  });

  testWidgets('aviso: los tres textos usan los tres tonos del estado (no los normales)',
      (tester) async {
    await pumpBrand(
      tester,
      const KuraStat(
        label: 'Bajo umbral',
        value: '7',
        meaning: '2 agotados',
        tone: KuraStatTone.warning,
      ),
    );
    const t = BrandTokens.kura;
    final strong = Tints.darkTone(t, t.statusWarning, 0.60);
    final soft = Tints.darkTone(t, t.statusWarning, 0.42);

    expect(colorOf(tester, 'Bajo umbral'), soft);
    expect(colorOf(tester, '7'), strong);
    expect(colorOf(tester, '2 agotados'), soft);

    // No son los tonos normales: la alarma sí recoloreó.
    expect(colorOf(tester, '7'), isNot(t.textPrimary));
    expect(colorOf(tester, 'Bajo umbral'), isNot(t.textSecondary));
    // Y derivan de aviso, no de peligro.
    expect(colorOf(tester, '7'), isNot(Tints.darkTone(t, t.statusDanger, 0.60)));
  });

  testWidgets('peligro: los tres textos derivan de statusDanger', (tester) async {
    await pumpBrand(
      tester,
      const KuraStat(
        label: 'Agotados',
        value: '3',
        meaning: 'sin existencia',
        tone: KuraStatTone.danger,
      ),
    );
    const t = BrandTokens.kura;
    expect(colorOf(tester, '3'), Tints.darkTone(t, t.statusDanger, 0.60));
    expect(colorOf(tester, 'Agotados'), Tints.darkTone(t, t.statusDanger, 0.42));
  });
}
