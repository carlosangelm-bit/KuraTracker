import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/widgets/kura_empty_state.dart';

import 'kura_test_helpers.dart';

void main() {
  testWidgets('rinde título, mensaje y SIEMPRE la acción que resuelve el vacío',
      (tester) async {
    var primary = 0;
    var secondary = 0;
    await pumpBrand(
      tester,
      KuraEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Aún no hay insumos',
        message: 'Agrega tu primer insumo para llevar el inventario.',
        primaryLabel: 'Agregar insumo',
        onPrimary: () => primary++,
        secondaryLabel: 'Cargar CSV',
        onSecondary: () => secondary++,
      ),
    );

    expect(find.text('Aún no hay insumos'), findsOneWidget);
    expect(find.text('Agrega tu primer insumo para llevar el inventario.'),
        findsOneWidget);
    expect(find.text('Agregar insumo'), findsOneWidget);
    expect(find.text('Cargar CSV'), findsOneWidget);

    await tester.tap(find.text('Agregar insumo'));
    await tester.tap(find.text('Cargar CSV'));
    expect(primary, 1);
    expect(secondary, 1);
  });
}
