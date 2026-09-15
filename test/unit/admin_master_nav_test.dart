// §13.3 — Un master que entra a Administración no debe perder Plataforma del riel.
// AdminSectionsShell construía el nav con `isMaster: false` CLAVADO; el arreglo lo toma de la
// sesión. El test de INVOCACIÓN (montar el shell con sesión master y mirar el riel) es CI-only
// —arrastra google_fonts—; aquí se cubre LOCAL con las dos piezas del arreglo:
//   (a) el nav como FUNCIÓN: con isMaster=true aparece /platform; como admin (isMaster=false),
//       no. Es la MISMA declaración que pinta el shell.
//   (b) una reja de fuente: admin_home pasa isMaster/isAdmin de la SESIÓN, no un literal.
// kuraNavDestinations no arrastra google_fonts → local y determinista.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/nav/kura_nav_destinations.dart';
import 'package:kuratracker/core/nav/nav_destination.dart';
import 'package:kuratracker/models/center_type.dart';

Set<String> _visibleRoutes({required bool isMaster}) => navFlattenVisible(
      kuraNavDestinations(
        moduleEnabled: (_) => true,
        isAdmin: !isMaster, // el otro caso real: admin de centro
        isMaster: isMaster,
        centerType: CenterType.clinicaHeridas,
      ),
    ).map((d) => d.route).toSet();

void main() {
  test('el nav del master contiene /platform; el del admin no', () {
    expect(_visibleRoutes(isMaster: true), contains('/platform'),
        reason: 'un master debe conservar Plataforma en su riel');
    expect(_visibleRoutes(isMaster: false), isNot(contains('/platform')),
        reason: 'un admin de centro no ve Plataforma');
  });

  test('admin_home construye el riel con el rol de la SESIÓN, no clavado', () {
    final src =
        File('lib/features/admin/admin_home_screen.dart').readAsStringSync();
    expect(src.contains('isMaster: sessionUser?.isMaster'), isTrue,
        reason: 'isMaster debe salir de la sesión');
    expect(src.contains('isAdmin: sessionUser?.isAdmin'), isTrue,
        reason: 'isAdmin debe salir de la sesión');
    expect(src.contains('isMaster: false'), isFalse,
        reason: 'ya no debe quedar isMaster clavado en false');
  });
}
