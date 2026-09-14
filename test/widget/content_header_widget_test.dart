// DIAGNÓSTICO LOCAL (sin router → sin google_fonts): valida la LÓGICA de
// KuraContentHeader aislada, para separar un fallo del widget de un fallo del montaje
// del router en content_header_test.dart (CI-only).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/nav/nav_destination.dart';

const _admin = NavDestination(
  label: 'Administración',
  icon: Icons.admin_panel_settings,
  route: '/admin',
  children: [
    NavDestination(label: 'Usuarios', icon: Icons.people, route: '/admin/usuarios'),
    NavDestination(label: 'Sitios', icon: Icons.place, route: '/admin/sitios'),
  ],
);

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('abierto: título con llave, área una sola vez', (t) async {
    await t.pumpWidget(_wrap(const KuraContentHeader(
      section: _admin,
      currentRoute: '/admin/usuarios',
      collapsed: false,
    )));
    expect(find.byKey(const ValueKey('content-header-title')), findsOneWidget);
    expect(find.text('Usuarios'), findsOneWidget); // el título
    expect(find.text('Administración'), findsOneWidget); // la sección padre
    expect(find.byType(KuraSectionMenu), findsNothing);
  });

  testWidgets('colapsado: menú de sección, área una sola vez (textContaining)',
      (t) async {
    await t.pumpWidget(_wrap(const KuraContentHeader(
      section: _admin,
      currentRoute: '/admin/usuarios',
      collapsed: true,
    )));
    expect(find.byType(KuraSectionMenu), findsOneWidget);
    expect(find.textContaining('Administración'), findsOneWidget);
    expect(find.byKey(const ValueKey('content-header-title')), findsNothing);
  });
}
