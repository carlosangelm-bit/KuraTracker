import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/nav/nav_destination.dart';

/// Declaración fija con un destino anidado, para probar la conducta del riel.
List<NavDestination> _fixture() => const [
      NavDestination(
          label: 'Pacientes', icon: Icons.people_outline, route: '/patients'),
      NavDestination(
        label: 'Administración',
        icon: Icons.settings_outlined,
        route: '/admin',
        children: [
          NavDestination(
              label: 'Configuración',
              icon: Icons.tune_outlined,
              route: '/admin/config'),
          NavDestination(
              label: 'Usuarios',
              icon: Icons.group_outlined,
              route: '/admin/usuarios'),
        ],
      ),
      NavDestination(
          label: 'Reportes', icon: Icons.bar_chart_outlined, route: '/reports'),
    ];

GoRouter _router(List<NavDestination> dests, {required bool collapsed}) {
  final routes = navFlattenVisible(dests).map((e) => e.route).toSet();
  return GoRouter(
    initialLocation: '/patients',
    routes: [
      for (final r in routes)
        GoRoute(
          path: r,
          builder: (c, s) => Scaffold(
            body: Row(children: [
              KuraNavRail(
                destinations: dests,
                currentRoute: s.uri.path,
                collapsed: collapsed,
              ),
              Expanded(child: Center(child: Text('SCREEN:$r'))),
            ]),
          ),
        ),
    ],
  );
}

Widget _app(GoRouter r) => MaterialApp.router(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      routerConfig: r,
    );

void main() {
  // Pantalla grande para el estado abierto.
  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('1 · cobertura de rutas: cada entrada monta su pantalla y queda activa',
      (tester) async {
    bigScreen(tester);
    final dests = _fixture();
    final router = _router(dests, collapsed: false);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    for (final e in navFlattenVisible(dests)) {
      router.go(e.route);
      await tester.pumpAndSettle();
      // La pantalla de esa ruta se montó.
      expect(find.text('SCREEN:${e.route}'), findsOneWidget, reason: e.route);
      // Y la entrada del riel quedó marcada como activa.
      expect(find.byKey(ValueKey('nav-active:${e.route}')), findsOneWidget,
          reason: e.route);
    }
  });

  test('1 · una entrada sin ruta válida rompe la declaración', () {
    expect(
      () => assertRoutesValid(const [
        NavDestination(label: 'Sin ruta', icon: Icons.error, route: '  '),
      ]),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('2 · nada se pierde al colapsar: iconos + menú del encabezado',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000); // < 1200 → colapsado
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dests = _fixture();
    final router = _router(dests, collapsed: true);
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    router.go('/admin/config');
    await tester.pumpAndSettle();

    // Cada DESTINO de primer nivel sigue alcanzable por su icono.
    for (final d in dests) {
      expect(find.byKey(ValueKey('nav-icon:${d.route}')), findsOneWidget,
          reason: d.route);
    }
    // Los HIJOS no están en el riel colapsado...
    expect(find.text('Configuración'), findsNothing);

    // ...pero el menú del encabezado los mantiene alcanzables.
    await tester.pumpWidget(_app(_router(dests, collapsed: true)));
    await tester.pumpAndSettle();
    final admin = dests.firstWhere((d) => d.route == '/admin');
    final menuRouter = GoRouter(
      initialLocation: '/admin/config',
      routes: [
        for (final c in admin.children)
          GoRoute(path: c.route, builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: '/host',
          builder: (_, s) => Scaffold(
            body: KuraSectionMenu(section: admin, currentRoute: '/admin/config'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(_app(menuRouter));
    menuRouter.go('/host');
    await tester.pumpAndSettle();

    // El menú abre y lista los hijos; seleccionar uno navega.
    await tester.tap(find.byType(KuraSectionMenu));
    await tester.pumpAndSettle();
    expect(find.text('Configuración'), findsWidgets);
    expect(find.text('Usuarios'), findsOneWidget);
    await tester.tap(find.text('Usuarios').last);
    await tester.pumpAndSettle();
    expect(menuRouter.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/usuarios');
  });

  test('4 · un solo nivel: una declaración con nietos falla con mensaje', () {
    final conNietos = const [
      NavDestination(
        label: 'Administración',
        icon: Icons.settings,
        route: '/admin',
        children: [
          NavDestination(
            label: 'Configuración',
            icon: Icons.tune,
            route: '/admin/config',
            children: [
              NavDestination(
                  label: 'Protocolo', icon: Icons.rule, route: '/admin/config/proto'),
            ],
          ),
        ],
      ),
    ];
    expect(() => assertSingleLevel(conNietos), throwsA(isA<StateError>()));
    // El mensaje nombra al culpable.
    expect(
      () => assertSingleLevel(conNietos),
      throwsA(predicate(
          (e) => e.toString().contains('Administración › Configuración'))),
    );
  });
}
