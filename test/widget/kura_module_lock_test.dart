import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/widgets/kura_module_lock.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

import 'kura_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Insumos vale $1,400/mes en el catálogo sembrado (0129 / demo_seed).
  const orgSin = 'lock-sin-modulo';
  const orgCon = 'lock-con-modulo';

  Future<DataRepository> repoWithOrgs() async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance(); // siembra billing_catalog
    // orgCon tiene el módulo insumos; orgSin no tiene nada.
    await store.upsert(Collections.orgEntitlements, {
      'id': '$orgCon-insumos',
      'organization_id': orgCon,
      'kind': 'module',
      'key': 'insumos',
      'status': 'active',
      'source': 'master',
    });
    return repo;
  }

  testWidgets('banda: rinde el precio de billing_catalog (\$1,400)',
      (tester) async {
    final repo = await repoWithOrgs();
    await pumpBrand(
      tester,
      KuraModuleLock.band(
        repo: repo,
        organizationId: orgSin,
        moduleKey: 'insumos',
        moduleName: 'Insumos',
        description: 'Inventario, mapeo, consumo y reabasto.',
      ),
    );
    expect(find.textContaining('\$1,400'), findsOneWidget);
    expect(find.text('Ver Licencias'), findsOneWidget);
  });

  testWidgets('sección: rinde "Agregar por \$1,400 al mes"', (tester) async {
    final repo = await repoWithOrgs();
    await pumpBrand(
      tester,
      KuraModuleLock.section(
        repo: repo,
        organizationId: orgSin,
        moduleKey: 'insumos',
        moduleName: 'Insumos',
        description: 'Lleva el control de tu inventario.',
      ),
    );
    expect(find.text('Agregar por \$1,400 al mes'), findsOneWidget);
  });

  testWidgets('acción bloqueada: al tocarla abre la sección con el precio',
      (tester) async {
    final repo = await repoWithOrgs();
    await pumpBrand(
      tester,
      KuraModuleLock.action(
        repo: repo,
        organizationId: orgSin,
        moduleKey: 'insumos',
        moduleName: 'Insumos',
        description: 'Lleva el control de tu inventario.',
        actionLabel: 'Cargar CSV',
      ),
    );
    // Se ve apagada, con su etiqueta; el precio aún no.
    expect(find.text('Cargar CSV'), findsOneWidget);
    expect(find.textContaining('\$1,400'), findsNothing);
    // Al tocarla abre el diálogo (densidad c) con el precio — nunca un snackbar.
    await tester.tap(find.text('Cargar CSV'));
    await tester.pumpAndSettle();
    expect(find.text('Agregar por \$1,400 al mes'), findsOneWidget);
  });

  testWidgets('no rinde nada cuando el módulo YA está contratado',
      (tester) async {
    final repo = await repoWithOrgs();
    await pumpBrand(
      tester,
      KuraModuleLock.band(
        repo: repo,
        organizationId: orgCon, // este SÍ tiene module:insumos
        moduleKey: 'insumos',
        moduleName: 'Insumos',
        description: 'Inventario, mapeo, consumo y reabasto.',
      ),
    );
    expect(find.text('Insumos'), findsNothing);
    expect(find.text('Ver Licencias'), findsNothing);
    expect(find.textContaining('\$1,400'), findsNothing);
  });
}
