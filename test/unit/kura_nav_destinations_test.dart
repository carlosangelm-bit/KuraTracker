import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/nav/kura_nav_destinations.dart';
import 'package:kuratracker/core/nav/nav_destination.dart';
import 'package:kuratracker/models/module_key.dart';

/// Las guardias (assertSingleLevel / assertRoutesValid) solo servían contra fixtures;
/// la declaración REAL no se validaba. Esta prueba las corre sobre kuraNavDestinations
/// mismo y, como recibe parámetros de visibilidad, sobre TODAS las permutaciones que
/// acepta (isAdmin × cada combinación de módulos habilitados) — no una sola.
///
/// Conducta: agregar un nieto a la declaración real, o dejar un destino con ruta vacía
/// o repetida, pone esto en rojo (verificado mutando el archivo real).
///
/// NOTA: si kuraNavDestinations gana una bandera nueva que cambie la lista, hay que
/// sumarla al producto de permutaciones de abajo.
void main() {
  final moduleKeys = ModuleKey.values.map((m) => m.dbValue).toList();
  final n = moduleKeys.length;

  test('la declaración real cumple las guardias en TODAS las permutaciones', () {
    // Producto: isAdmin ∈ {true,false} × todas las combinaciones de módulos (2^n).
    for (final isAdmin in [true, false]) {
      for (var mask = 0; mask < (1 << n); mask++) {
        final enabled = <String>{
          for (var i = 0; i < n; i++)
            if (mask & (1 << i) != 0) moduleKeys[i],
        };
        final decl = kuraNavDestinations(
          moduleEnabled: (k) => enabled.contains(k),
          isAdmin: isAdmin,
        );
        expect(
          () {
            assertSingleLevel(decl);
            assertRoutesValid(decl);
          },
          returnsNormally,
          reason: 'isAdmin=$isAdmin, módulos=$enabled',
        );
      }
    }
  });
}
