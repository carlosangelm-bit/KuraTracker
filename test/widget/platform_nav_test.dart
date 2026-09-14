import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_destinations.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/nav/nav_destination.dart';

/// Etapa 2: /platform cableado al KuraNavRail. Las nueve secciones se declaran en
/// kuraNavDestinations (vía platformNavDestinations), cada una con su URL propia.
/// Pruebas 1 y 2 de §4 SOBRE LAS NUEVE (no una muestra).
void main() {
  const expected = <String, String>{
    'Centros': '/platform/centros',
    'Usuarios': '/platform/usuarios',
    'Personal': '/platform/personal',
    'Sitios': '/platform/sitios',
    'Catálogo': '/platform/catalogo',
    'Marca': '/platform/marca',
    'Módulos': '/platform/modulos',
    'Solicitudes': '/platform/solicitudes',
    'Licencia': '/platform/licencia',
  };

  Widget app(GoRouter r) => MaterialApp.router(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
        routerConfig: r,
      );

  test('la declaración trae EXACTAMENTE las nueve secciones, con su URL', () {
    final plataforma = platformNavDestinations().single;
    expect(plataforma.route, '/platform');
    final got = {for (final c in plataforma.children) c.label: c.route};
    expect(got, expected);
    // Licencia —que vivía en el caso 8— tiene ahora su ruta.
    expect(got['Licencia'], '/platform/licencia');
  });

  testWidgets('1 · cada una de las nueve monta su pantalla y queda activa',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navs = platformNavDestinations();
    final routes = navFlattenVisible(navs).map((e) => e.route).toSet();
    final router = GoRouter(
      initialLocation: '/platform/centros',
      routes: [
        for (final r in routes)
          GoRoute(
            path: r,
            builder: (c, s) => Scaffold(
              body: Row(children: [
                KuraNavRail(
                    destinations: navs, currentRoute: s.uri.path, collapsed: false),
                Expanded(child: Center(child: Text('SCREEN:$r'))),
              ]),
            ),
          ),
      ],
    );
    await tester.pumpWidget(app(router));
    await tester.pumpAndSettle();

    for (final route in expected.values) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(find.text('SCREEN:$route'), findsOneWidget, reason: route);
      expect(find.byKey(ValueKey('nav-active:$route')), findsOneWidget,
          reason: route);
    }
  });

  testWidgets('1b · entrar en frío a /platform y a cada sección llega correcto',
      (tester) async {
    // Réplica de la estructura de rutas de app_router: /platform canoniza a Centros
    // y /platform/:section resuelve la sección tecleada.
    final router = GoRouter(
      initialLocation: '/patients',
      routes: [
        GoRoute(path: '/patients', builder: (_, __) => const Text('otra')),
        GoRoute(
          path: '/platform',
          redirect: (c, s) =>
              s.matchedLocation == '/platform' ? '/platform/centros' : null,
        ),
        GoRoute(
          path: '/platform/:section',
          builder: (c, s) => Text('SECTION:${s.pathParameters['section']}'),
        ),
      ],
    );
    await tester.pumpWidget(app(router));
    await tester.pumpAndSettle();

    // En frío a /platform → Centros.
    router.go('/platform');
    await tester.pumpAndSettle();
    expect(find.text('SECTION:centros'), findsOneWidget);

    // En frío a cada sección → esa sección.
    for (final route in expected.values) {
      final section = route.split('/').last;
      router.go(route);
      await tester.pumpAndSettle();
      expect(find.text('SECTION:$section'), findsOneWidget, reason: route);
    }
  });

  testWidgets('2 · nada se pierde al colapsar: icono + menú Plataforma › Sección',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000); // < 1200 → colapsado
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navs = platformNavDestinations();
    final plataforma = navs.single;

    // Riel colapsado: Plataforma por su icono; los hijos NO están en el riel.
    final railRouter = GoRouter(
      initialLocation: '/platform/usuarios',
      routes: [
        GoRoute(
          path: '/platform/usuarios',
          builder: (c, s) => Scaffold(
            body: KuraNavRail(
                destinations: navs,
                currentRoute: '/platform/usuarios',
                collapsed: true),
          ),
        ),
      ],
    );
    await tester.pumpWidget(app(railRouter));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-icon:/platform')), findsOneWidget);
    expect(find.text('Centros'), findsNothing); // hijos fuera del riel colapsado

    // El menú del encabezado mantiene alcanzables LAS NUEVE.
    final menuRouter = GoRouter(
      initialLocation: '/host',
      routes: [
        for (final r in expected.values)
          GoRoute(path: r, builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: '/host',
          builder: (_, __) => Scaffold(
            body: KuraSectionMenu(
                section: plataforma, currentRoute: '/platform/usuarios'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(app(menuRouter));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(KuraSectionMenu));
    await tester.pumpAndSettle();
    for (final label in expected.keys) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    // Seleccionar una navega a su ruta.
    await tester.tap(find.text('Licencia').last);
    await tester.pumpAndSettle();
    expect(menuRouter.routerDelegate.currentConfiguration.uri.toString(),
        '/platform/licencia');
  });
}
