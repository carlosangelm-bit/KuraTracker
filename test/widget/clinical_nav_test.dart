// §9 — Pruebas de la navegación clínica (etapa 5): el riel nuevo (KuraNavRail) y la
// barra inferior salen de la MISMA declaración (kuraNavDestinations), en las rutas
// clínicas, para todos. Reemplazan al inventario manual `_itemsFor` de AppShell.
//
// P1: riel ≡ barra — para las mismas banderas, el conjunto de destinos del riel y el de
//     la barra (primarios + desbordamiento) es idéntico. Reemplaza "cierre de la clase".
// P2: la rama por tipo de centro sobrevive EN LA BARRA (teléfono): hospital → Rondas
//     (/prevention-agenda); clínica → Agenda (/agenda). Es la regresión que ya tuvimos.
// P3: tres bandas, sobre el router real: 1400 riel abierto; 1000 colapsado; 800 sin
//     riel y con barra inferior.
// P4: AppShell ya NO pinta riel de escritorio en NINGUNA ruta clínica (se fue el
//     NavigationRail viejo; ahora es el KuraNavRail de la declaración). Cierra la etapa.
// Cuidador: la declaración devuelve EXACTAMENTE un destino (/caregiver); sin barra ni
//     riel (regla de ≥2). Rojo si algún destino clínico quedara visible para el cuidador.
//
// Cada una con el criterio de siempre: romper la regla la pone en rojo, verificado a
// mano antes de darla por verde.
//
// CI-ONLY (las de router real): importar app_router arrastra todas las pantallas →
// google_fonts; `flutter analyze` valida y corre en CI (3.27.1). Las PURAS corren local.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/kura_nav_destinations.dart';
import 'package:kuratracker/core/nav/kura_nav_rail.dart';
import 'package:kuratracker/core/nav/nav_destination.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_router.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/center_type.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';

// --------------------------------------------------------------------------- Fixtures
const _admin = AppUser(
  id: 'a1',
  role: AppRole.admin,
  fullName: 'Admin Uno',
  email: 'a@x.test',
  organizationId: 'org-demo',
  staffId: 's1',
);

const _caregiver = AppUser(
  id: 'c1',
  role: AppRole.cuidador,
  fullName: 'Cuidador Uno',
  email: 'c@x.test',
  organizationId: 'org-demo',
);

const _clinicalMods = <ModuleKey>{
  ModuleKey.patients,
  ModuleKey.agenda,
  ModuleKey.prevention,
  ModuleKey.reports,
};

// --------------------------------------------------------------------------- P1 (pura)
Set<String> _railSet(List<NavDestination> navs) =>
    navs.where((d) => d.isVisible).map((d) => d.route).toSet();

Set<String> _barSet(List<NavDestination> navs) {
  final split = navBottomBarSplit(navs);
  return {...split.primary, ...split.overflow}.map((d) => d.route).toSet();
}

// ------------------------------------------------------- Harness del router real (P2-P4)
class _FakeSession extends SessionController {
  _FakeSession(AppUser user, CenterType centerType) {
    state = SessionState(user: user, activeCenterType: centerType);
  }
}

void _resize(WidgetTester t, double w) {
  t.view.physicalSize = Size(w, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> _open(WidgetTester t, AppUser user, Set<ModuleKey> mods, String route,
    double w,
    {CenterType centerType = CenterType.clinicaHeridas}) async {
  _resize(t, w);
  final repo = await DataRepository.instance();
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith((ref) => _FakeSession(user, centerType)),
    dataRepositoryProvider.overrideWith((ref) => repo),
    enabledModulesProvider.overrideWithValue(mods),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      routerConfig: router,
    ),
  ));
  await t.pumpAndSettle();
  router.go(route);
  await t.pumpAndSettle();
}

Finder _inBar(String label) => find.descendant(
    of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // --------------------------------------------------------------- P1 riel ≡ barra
  test('§9·1 · riel ≡ barra: mismo conjunto de destinos para las mismas banderas', () {
    // Matriz de banderas representativas (rol, módulos, tipo de centro, cuidador).
    final cases = <(String, List<NavDestination>)>[
      (
        'admin · clínica · todos los módulos',
        kuraNavDestinations(
            moduleEnabled: (_) => true,
            isAdmin: true,
            isMaster: false,
            centerType: CenterType.clinicaHeridas)
      ),
      (
        'admin · hospital · todos los módulos',
        kuraNavDestinations(
            moduleEnabled: (_) => true,
            isAdmin: true,
            isMaster: false,
            centerType: CenterType.hospital)
      ),
      (
        'clínico · clínica · algunos módulos',
        kuraNavDestinations(
            moduleEnabled: (k) => k == ModuleKey.patients.dbValue,
            isAdmin: false,
            isMaster: false,
            centerType: CenterType.clinicaHeridas)
      ),
      (
        'master',
        kuraNavDestinations(
            moduleEnabled: (_) => false,
            isAdmin: false,
            isMaster: true,
            centerType: CenterType.clinicaHeridas)
      ),
      (
        'cuidador',
        kuraNavDestinations(
            moduleEnabled: (_) => true,
            isAdmin: true,
            isMaster: false,
            centerType: CenterType.clinicaHeridas,
            isCaregiverOnly: true)
      ),
    ];
    for (final (desc, navs) in cases) {
      expect(_barSet(navs), _railSet(navs),
          reason: 'riel y barra deben coincidir — $desc');
      // Partición real: ningún destino cae en primarios Y desbordamiento a la vez.
      final split = navBottomBarSplit(navs);
      final overlap = split.primary.toSet().intersection(split.overflow.toSet());
      expect(overlap, isEmpty, reason: 'primario ∩ desbordamiento no vacío — $desc');
    }
  });

  // ---------------------------------------------------------- Cuidador (declaración)
  test('§9 · cuidador: la declaración devuelve EXACTAMENTE un destino (/caregiver)', () {
    // Aun con TODOS los módulos y isAdmin=true, ser cuidador oculta todo lo demás.
    // Rojo si a algún destino clínico le faltara la condición !isCaregiverOnly.
    final navs = kuraNavDestinations(
      moduleEnabled: (_) => true,
      isAdmin: true,
      isMaster: false,
      centerType: CenterType.clinicaHeridas,
      isCaregiverOnly: true,
    );
    expect(_railSet(navs), {'/caregiver'});
  });

  // ------------------------------------------------- P2 rama por tipo de centro (barra)
  testWidgets('§9·2 · barra (teléfono): hospital → Rondas; clínica → Agenda',
      (t) async {
    // Hospital: la barra ancla "Rondas", nunca "Agenda".
    await _open(t, _admin, _clinicalMods, '/', 800,
        centerType: CenterType.hospital);
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'a 800 px debe pintarse la barra inferior');
    expect(_inBar('Rondas'), findsOneWidget);
    expect(_inBar('Agenda'), findsNothing);

    // Clínica de heridas: la barra ancla "Agenda", nunca "Rondas".
    await _open(t, _admin, _clinicalMods, '/', 800,
        centerType: CenterType.clinicaHeridas);
    expect(_inBar('Agenda'), findsOneWidget);
    expect(_inBar('Rondas'), findsNothing);
  });

  // --------------------------------------------------------------- P3 tres bandas
  testWidgets('§9·3 · tres bandas: 1400 abierto, 1000 colapsado, 800 barra',
      (t) async {
    // Banda 1 (≥1200): riel ABIERTO — existe el botón "Colapsar".
    await _open(t, _admin, _clinicalMods, '/patients', 1400);
    expect(find.byType(KuraNavRail), findsOneWidget);
    expect(find.byTooltip('Colapsar'), findsOneWidget,
        reason: 'a 1400 el riel está abierto');
    expect(find.byType(NavigationBar), findsNothing);

    // Banda 2 (900–1199): riel COLAPSADO — existe "Expandir", no "Colapsar".
    await _open(t, _admin, _clinicalMods, '/patients', 1000);
    expect(find.byType(KuraNavRail), findsOneWidget);
    expect(find.byTooltip('Expandir'), findsOneWidget,
        reason: 'a 1000 el riel está colapsado');
    expect(find.byType(NavigationBar), findsNothing);

    // Banda 3 (<900): SIN riel, CON barra inferior.
    await _open(t, _admin, _clinicalMods, '/patients', 800);
    expect(find.byType(KuraNavRail), findsNothing,
        reason: 'a 800 no hay riel de escritorio');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  // --------------------------------------------- P4 (cierre): sin NavigationRail viejo
  testWidgets('§9·4 · AppShell no pinta riel de escritorio (se fue el NavigationRail)',
      (t) async {
    // Antes de la etapa 5 AppShell pintaba un NavigationRail (Material) en las clínicas
    // en paralelo al KuraNavRail de /admin y /platform — la costura de dos navegaciones.
    // Rojo si AppShell volviera a pintar su NavigationRail viejo.
    await _open(t, _admin, _clinicalMods, '/patients', 1400);
    expect(find.byType(NavigationRail), findsNothing,
        reason: 'no debe quedar ningún NavigationRail de Material');
    expect(find.byType(KuraNavRail), findsOneWidget,
        reason: 'el único riel de escritorio es el KuraNavRail de la declaración');
  });

  // ----------------------------------------------- Cuidador (router real): sin chrome
  testWidgets('§9 · cuidador (router real): sin barra ni riel', (t) async {
    await _open(t, _caregiver, const {}, '/caregiver', 800);
    expect(find.byType(KuraNavRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing,
        reason: 'un solo destino no pinta barra (regla de ≥2)');
  });
}
