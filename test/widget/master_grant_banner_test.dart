// LA REGLA DEL MASTER, cableada una vez en KuraModuleLock. Para un MASTER que mira un
// centro SIN el módulo: en lugar del muro de venta va el banner de otorgamiento que
// (1) nombra el centro, (2) NO muestra precio ni "ver planes", (3) ofrece [Otorgar].
// Para quien NO es master, el muro de venta sigue igual.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/providers/master_grant_provider.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/widgets/kura_module_lock.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

class _FakeSessionController extends SessionController {
  _FakeSessionController(AppUser? user) {
    state = SessionState(user: user);
  }
}

AppUser _user(AppRole role) => AppUser(
      id: 'u-${role.name}',
      role: role,
      fullName: 'X',
      email: 'x@y.test',
      organizationId: 'home',
    );

const _org = 'centro-sin-insumos';
const _orgName = 'Prueba Fase 2';

Future<void> _pump(
  WidgetTester t,
  DataRepository repo, {
  required AppUser? user,
  MasterGrantLauncher? launcher,
}) async {
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ProviderScope(
    overrides: [
      sessionProvider.overrideWith((ref) => _FakeSessionController(user)),
      if (launcher != null)
        masterGrantLauncherProvider.overrideWith((ref) => launcher),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: Scaffold(
        body: KuraModuleLock.section(
          repo: repo,
          organizationId: _org,
          moduleKey: 'insumos',
          moduleName: 'Insumos',
          description: 'Inventario por sede, consumo y costeo.',
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<DataRepository> repoWithNamedCenterNoModule() async {
    // El repo se construye PRIMERO (su seed demo corre aquí); luego se agrega el centro,
    // para que el seed no lo pise. billing_catalog sembrado → hay precio que ocultar.
    final repo = await DataRepository.instance();
    final store = await LocalStore.instance();
    // Centro CON nombre pero SIN el módulo Insumos (sin org_entitlement de insumos).
    await store.upsert(Collections.organizations, {'id': _org, 'name': _orgName});
    return repo;
  }

  testWidgets('MASTER: banner que nombra el centro, sin precio ni "ver planes"',
      (t) async {
    final repo = await repoWithNamedCenterNoModule();
    await _pump(t, repo,
        user: _user(AppRole.master),
        launcher: (ctx, {required organizationId, required moduleKey, required moduleName}) async => false);

    // (1) nombra el centro por su nombre.
    expect(find.textContaining('«$_orgName» no tiene el módulo Insumos'),
        findsOneWidget);
    // (3) ofrece otorgar.
    expect(find.text('Otorgar Insumos'), findsOneWidget);
    // (2) NUNCA muro de venta para el master: sin precio ni salida a Licencias.
    expect(find.textContaining('/mes'), findsNothing);
    expect(find.text('Ver Licencias'), findsNothing);
    expect(find.textContaining('Agregar por'), findsNothing);
  });

  testWidgets('MASTER: [Otorgar] llama al lanzador con el centro y el módulo',
      (t) async {
    final repo = await repoWithNamedCenterNoModule();
    String? gotOrg;
    String? gotModule;
    await _pump(t, repo,
        user: _user(AppRole.master),
        launcher: (ctx, {required organizationId, required moduleKey, required moduleName}) async {
      gotOrg = organizationId;
      gotModule = moduleKey;
      return false;
    });
    await t.tap(find.text('Otorgar Insumos'));
    await t.pumpAndSettle();
    expect(gotOrg, _org);
    expect(gotModule, 'insumos');
  });

  testWidgets('NO master: sigue el muro de venta (precio), sin banner de otorgamiento',
      (t) async {
    final repo = await repoWithNamedCenterNoModule();
    // admin del centro: es quien puede comprar → ve el muro con precio.
    await _pump(t, repo, user: _user(AppRole.admin), launcher: null);
    expect(find.text('Otorgar Insumos'), findsNothing);
    expect(find.textContaining('«$_orgName»'), findsNothing);
    // El muro dice el precio / lleva a Licencias.
    expect(find.textContaining('Agregar por'), findsOneWidget);
  });
}
