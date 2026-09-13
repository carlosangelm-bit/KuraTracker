import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/widgets/kura_data_table.dart';

import 'kura_test_helpers.dart';

void main() {
  final columns = const [
    KuraColumn(label: 'Nombre', sortable: true),
    KuraColumn(label: 'Piezas', numeric: true, sortable: true),
  ];

  testWidgets('ordena por la columna que se toca', (tester) async {
    await pumpBrand(
      tester,
      KuraDataTable(
        columns: columns,
        rows: [
          KuraRow(id: 'c', cells: [KuraCell.text('Charlie'), KuraCell.number(3)]),
          KuraRow(id: 'a', cells: [KuraCell.text('Alice'), KuraCell.number(1)]),
          KuraRow(id: 'b', cells: [KuraCell.text('Bob'), KuraCell.number(2)]),
        ],
      ),
    );

    // Sin ordenar: el orden es el dado (Charlie, Alice, Bob).
    expect(tester.getTopLeft(find.text('Charlie')).dy,
        lessThan(tester.getTopLeft(find.text('Alice')).dy));

    // Tocar el encabezado "Nombre" ordena ascendente: Alice < Bob < Charlie.
    await tester.tap(find.text('NOMBRE'));
    await tester.pumpAndSettle();
    final yAlice = tester.getTopLeft(find.text('Alice')).dy;
    final yBob = tester.getTopLeft(find.text('Bob')).dy;
    final yCharlie = tester.getTopLeft(find.text('Charlie')).dy;
    expect(yAlice, lessThan(yBob));
    expect(yBob, lessThan(yCharlie));

    // Tocar otra vez invierte a descendente: Charlie < Bob < Alice.
    await tester.tap(find.text('NOMBRE'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Charlie')).dy,
        lessThan(tester.getTopLeft(find.text('Alice')).dy));
  });

  testWidgets('la casilla del encabezado marca todas', (tester) async {
    Set<Object> selected = {};
    await pumpBrand(
      tester,
      KuraDataTable(
        selectable: true,
        onSelectionChanged: (s) => selected = s,
        columns: columns,
        rows: [
          KuraRow(id: 'a', cells: [KuraCell.text('Alice'), KuraCell.number(1)]),
          KuraRow(id: 'b', cells: [KuraCell.text('Bob'), KuraCell.number(2)]),
          KuraRow(id: 'c', cells: [KuraCell.text('Charlie'), KuraCell.number(3)]),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('kura-header-checkbox')));
    await tester.pumpAndSettle();
    expect(selected, {'a', 'b', 'c'});

    // Tocarla de nuevo las desmarca todas.
    await tester.tap(find.byKey(const ValueKey('kura-header-checkbox')));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
  });
}
