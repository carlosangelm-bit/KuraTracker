import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_destinations.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/nav/nav_destination.dart';
import 'package:kuratracker/models/center_type.dart';

/// Etapa 3: /admin cableado al KuraNavRail. Es el caso "Main" del canvas — la tira
/// externa (ocho destinos clínicos reales) se convierte en los destinos de primer
/// nivel del riel, con Administración anidando sus SEIS hijos, cada uno con su URL.
/// Pruebas 1 y 2 de §4 sobre las seis secciones.
List<NavDestination> _adminNav(
        {CenterType centerType = CenterType.clinicaHeridas}) =>
    kuraNavDestinations(
      moduleEnabled: (_) => true, // todos los módulos, para ver los de primer nivel
      isAdmin: true,
      isMaster: false,
      centerType: centerType,
    );

Set<String> _visibleRoutes(List<NavDestination> nav) =>
    navFlattenVisible(nav).map((e) => e.route).toSet();

void main() {
  const expected = <String, String>{
    'Usuarios': '/admin/usuarios',
    'Personal': '/admin/personal',
    'Sitios': '/admin/sitios',
    'Configuración': '/admin/configuracion',
    // Las 8 profundas ahora viven en el riel (antes eran pantallas completas fuera
    // del shell). Enumeradas aquí: si se agrega/quita una, esta prueba lo caza.
    'Protocolo Kura+': '/admin/protocolo-kura',
    'Matriz del protocolo': '/admin/productos-protocolo',
    'Escalas del protocolo': '/admin/escalas-protocolo',
    'Fuente de recomendaciones': '/admin/fuente-recomendaciones',
    'Tipos de cita': '/admin/tipo-cita-sesiones',
    'Tipos de consulta': '/admin/tipos-consulta',
    'Registro de divulgaciones': '/admin/divulgaciones',
    'Depurar expedientes': '/admin/depurar-expedientes',
    'Marca': '/admin/marca',
    'Licencias': '/admin/licencias',
  };

  Widget app(GoRouter r) => MaterialApp.router(
        theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
        routerConfig: r,
      );

  test('Administración anida EXACTAMENTE las seis secciones, con su URL', () {
    final admin = _adminNav().firstWhere((d) => d.route == '/admin');
    final got = {for (final c in admin.children) c.label: c.route};
    expect(got, expected);
  });

  test('los destinos clínicos son de PRIMER nivel (Inicio, Pacientes, …)', () {
    final tops = _adminNav().map((d) => d.route).toSet();
    expect(tops, containsAll(['/', '/patients', '/admin']));
    // Administración no es de primer nivel "plano": tiene hijos.
    final admin = _adminNav().firstWhere((d) => d.route == '/admin');
    expect(admin.hasChildren, isTrue);
  });

  test('agenda por tipo de centro: hospital → Rondas; clínica → Agenda', () {
    // La regresión: en hospital /agenda sale "no configurada"; el eje son las Rondas.
    final hospital = _adminNav(centerType: CenterType.hospital);
    final hRoutes = _visibleRoutes(hospital);
    expect(hRoutes, contains('/prevention-agenda'));
    expect(hRoutes, isNot(contains('/agenda')));
    expect(
        hospital.firstWhere((d) => d.route == '/prevention-agenda').label,
        'Rondas');

    final clinica = _adminNav(centerType: CenterType.clinicaHeridas);
    final cRoutes = _visibleRoutes(clinica);
    expect(cRoutes, contains('/agenda'));
    expect(cRoutes, isNot(contains('/prevention-agenda')));
    expect(clinica.firstWhere((d) => d.route == '/agenda').label, 'Agenda');
  });

  // NOTA (§5 etapa 5): el test "cierre de la clase" —que comparaba a mano cada destino
  // condicional contra la lista `moduleGated` de app_shell.dart— se ELIMINÓ. Al retirar
  // `_itemsFor` de AppShell, ya no hay una segunda lista contra la cual comparar: la
  // declaración es la ÚNICA fuente. Lo sustituye la prueba 1 del §9 (riel ≡ barra), en
  // clinical_nav_test.dart, que impide que el riel y la barra vuelvan a separarse.

  testWidgets('1 · cada una de las seis monta su pantalla y queda activa',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navs = _adminNav();
    final routes = navFlattenVisible(navs).map((e) => e.route).toSet();
    final router = GoRouter(
      initialLocation: '/admin/usuarios',
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

  testWidgets('2 · nada se pierde al colapsar: icono + menú Administración › Sección',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000); // < 1200 → colapsado
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navs = _adminNav();
    final admin = navs.firstWhere((d) => d.route == '/admin');

    final railRouter = GoRouter(
      initialLocation: '/admin/usuarios',
      routes: [
        GoRoute(
          path: '/admin/usuarios',
          builder: (c, s) => Scaffold(
            body: KuraNavRail(
                destinations: navs,
                currentRoute: '/admin/usuarios',
                collapsed: true),
          ),
        ),
      ],
    );
    await tester.pumpWidget(app(railRouter));
    await tester.pumpAndSettle();
    // Administración alcanzable por su icono; los hijos NO están en el riel colapsado.
    expect(find.byKey(const ValueKey('nav-icon:/admin')), findsOneWidget);
    expect(find.text('Configuración'), findsNothing);

    // El menú del encabezado mantiene alcanzables LAS SEIS.
    final menuRouter = GoRouter(
      initialLocation: '/host',
      routes: [
        for (final r in expected.values)
          GoRoute(path: r, builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: '/host',
          builder: (_, __) => Scaffold(
            body: KuraSectionMenu(
                section: admin, currentRoute: '/admin/usuarios'),
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
    await tester.tap(find.text('Licencias').last);
    await tester.pumpAndSettle();
    expect(menuRouter.routerDelegate.currentConfiguration.uri.toString(),
        '/admin/licencias');
  });
}
