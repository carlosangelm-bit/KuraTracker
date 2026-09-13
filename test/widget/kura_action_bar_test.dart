import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/widgets/kura_action_bar.dart';

import 'kura_test_helpers.dart';

void main() {
  testWidgets('rinde buscador, acción primaria, filtros con conteo y "Mostrando N de M"',
      (tester) async {
    var tapped = '';
    var primary = 0;
    await pumpBrand(
      tester,
      KuraActionBar(
        searchHint: 'Buscar por nombre, SKU o proveedor',
        onSearchChanged: (_) {},
        primaryLabel: 'Nuevo insumo',
        onPrimary: () => primary++,
        moreActions: [
          KuraMenuAction(label: 'Descargar plantilla CSV', onSelected: () {}),
        ],
        filters: [
          KuraFilter(
              label: 'Bajo umbral',
              count: 7,
              selected: false,
              onTap: () => tapped = 'bajo'),
          KuraFilter(
              label: 'Agotados', count: 2, selected: true, onTap: () {}),
        ],
        showingText: 'Mostrando 12 de 40',
      ),
    );

    expect(find.text('Buscar por nombre, SKU o proveedor'), findsOneWidget);
    expect(find.text('Nuevo insumo'), findsOneWidget);
    expect(find.text('Más acciones'), findsOneWidget);
    // Cada pastilla trae su conteo.
    expect(find.text('Bajo umbral · 7'), findsOneWidget);
    expect(find.text('Agotados · 2'), findsOneWidget);
    expect(find.text('Mostrando 12 de 40'), findsOneWidget);

    await tester.tap(find.text('Nuevo insumo'));
    expect(primary, 1);
    await tester.tap(find.text('Bajo umbral · 7'));
    expect(tapped, 'bajo');

    // "Más acciones" abre el menú con el nombre COMPLETO.
    await tester.tap(find.text('Más acciones'));
    await tester.pumpAndSettle();
    expect(find.text('Descargar plantilla CSV'), findsOneWidget);
  });
}
