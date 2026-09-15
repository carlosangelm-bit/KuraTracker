import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/nav/nav_destination.dart';

/// §3/§10.5: «Ayuda» vive al pie del riel (junto al menú de cuenta) y es alcanzable en los
/// DOS estados del riel — abierto (240 px) y colapsado (72 px), no solo abierto. Se prueba
/// el componente aislado (KuraNavRail no arrastra google_fonts): el shell provee [onHelp];
/// en la demo (onHelp == null) no se pinta el control (el asistente vive detrás de Supabase).
List<NavDestination> _fixture() => const [
      NavDestination(
          label: 'Pacientes', icon: Icons.people_outline, route: '/patients'),
      NavDestination(
          label: 'Reportes', icon: Icons.bar_chart_outlined, route: '/reports'),
    ];

Widget _rail({required bool collapsed, VoidCallback? onHelp}) => MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: Scaffold(
        body: Row(children: [
          KuraNavRail(
            destinations: _fixture(),
            currentRoute: '/patients',
            collapsed: collapsed,
            userName: 'Ana',
            onHelp: onHelp,
          ),
          const Expanded(child: SizedBox()),
        ]),
      ),
    );

void main() {
  final help = find.byKey(const ValueKey('rail-help'));

  testWidgets('Ayuda alcanzable y accionable en el riel ABIERTO', (t) async {
    var taps = 0;
    await t.pumpWidget(_rail(collapsed: false, onHelp: () => taps++));
    expect(help, findsOneWidget);
    await t.tap(help);
    expect(taps, 1);
  });

  testWidgets('Ayuda alcanzable y accionable en el riel COLAPSADO (72 px)',
      (t) async {
    var taps = 0;
    await t.pumpWidget(_rail(collapsed: true, onHelp: () => taps++));
    expect(help, findsOneWidget, reason: 'no solo abierto: también colapsado');
    await t.tap(help);
    expect(taps, 1);
  });

  testWidgets('Sin onHelp (demo) no hay control de Ayuda en el riel', (t) async {
    await t.pumpWidget(_rail(collapsed: false, onHelp: null));
    expect(help, findsNothing);
    await t.pumpWidget(_rail(collapsed: true, onHelp: null));
    expect(help, findsNothing);
  });
}
