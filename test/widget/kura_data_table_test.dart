import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/widgets/kura_data_table.dart';

import 'kura_test_helpers.dart';

void main() {
  final columns = const [
    KuraColumn(label: 'Nombre', sortable: true),
    KuraColumn(label: 'Piezas', numeric: true, sortable: true),
  ];

  List<KuraRow> threeRows() => [
        KuraRow(id: 'c', cells: [KuraCell.text('Charlie'), KuraCell.number(3)]),
        KuraRow(id: 'a', cells: [KuraCell.text('Alice'), KuraCell.number(1)]),
        KuraRow(id: 'b', cells: [KuraCell.text('Bob'), KuraCell.number(2)]),
      ];

  testWidgets('ordena por la columna que se toca', (tester) async {
    await pumpBrand(tester, KuraDataTable(columns: columns, rows: threeRows()));

    // Sin ordenar: el orden es el dado (Charlie, Alice, Bob).
    expect(tester.getTopLeft(find.text('Charlie')).dy,
        lessThan(tester.getTopLeft(find.text('Alice')).dy));

    // Tocar "Nombre" ordena ascendente: Alice < Bob < Charlie.
    await tester.tap(find.text('NOMBRE'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Alice')).dy,
        lessThan(tester.getTopLeft(find.text('Bob')).dy));
    expect(tester.getTopLeft(find.text('Bob')).dy,
        lessThan(tester.getTopLeft(find.text('Charlie')).dy));

    // Tocar otra vez invierte a descendente.
    await tester.tap(find.text('NOMBRE'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Charlie')).dy,
        lessThan(tester.getTopLeft(find.text('Alice')).dy));
  });

  testWidgets('orden inicial: por la columna dada, ascendente', (tester) async {
    await pumpBrand(
      tester,
      KuraDataTable(
        columns: columns,
        rows: threeRows(),
        initialSortColumn: 0,
        initialSortAscending: true,
      ),
    );
    // De fábrica, sin tocar nada: Alice < Bob < Charlie.
    expect(tester.getTopLeft(find.text('Alice')).dy,
        lessThan(tester.getTopLeft(find.text('Charlie')).dy));
  });

  testWidgets(
      'selección CONTROLADA: el encabezado marca todas y el padre puede limpiarla',
      (tester) async {
    Set<Object> selected = {};
    await pumpBrand(
      tester,
      StatefulBuilder(
        builder: (ctx, setState) => Column(
          children: [
            KuraDataTable(
              selectable: true,
              selected: selected,
              onSelectionChanged: (s) => setState(() => selected = s),
              columns: columns,
              rows: threeRows(),
            ),
            TextButton(
              onPressed: () => setState(() => selected = {}),
              child: const Text('Limpiar'),
            ),
          ],
        ),
      ),
    );

    // Nada marcado (la palomita solo aparece en casillas encendidas).
    expect(find.byIcon(Icons.check), findsNothing);

    // La casilla del encabezado marca todas: encabezado + 3 filas = 4 palomitas.
    await tester.tap(find.byKey(const ValueKey('kura-header-checkbox')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsNWidgets(4));
    expect(selected, {'a', 'b', 'c'});

    // El PADRE limpia la selección (lo que antes era imposible con estado interno).
    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsNothing);
    expect(selected, isEmpty);
  });

  testWidgets('money(null) pinta "—", no "\$0"', (tester) async {
    await pumpBrand(
      tester,
      KuraDataTable(
        columns: const [
          KuraColumn(label: 'Concepto'),
          KuraColumn(label: 'Precio', numeric: true),
        ],
        rows: [
          KuraRow(id: '1', cells: [KuraCell.text('Con precio'), KuraCell.money(110400)]),
          KuraRow(id: '2', cells: [KuraCell.text('Sin precio'), KuraCell.money(null)]),
        ],
      ),
    );
    expect(find.text('\$1,104.00'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('\$0.00'), findsNothing);
  });
}
