import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/features/platform/derechos/center_license_data.dart';
import 'package:kuratracker/features/platform/derechos/module_agreement.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// Corrección (a): module:clinico es la PRIMERA fila de Módulos, y existe el estado
/// "con asientos, sin module:clinico" — 0119 deriva el módulo de los asientos, así
/// que un centro con seat:clinico activo y module:clinico en canceled tiene el
/// expediente prendido pero SIN derecho: nadie lo ve. Debe pintar el caso rojo.
///
/// Conducta: quitar la fila de module:clinico de _moduleDescriptors deja sin fila
/// 'clinico' → firstWhere lanza y la prueba cae.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('seat:clinico activo + module:clinico canceled → primera fila, caso rojo',
      () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'clic-red-org';

    // Asientos clínicos activos: el expediente está en uso.
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-seat',
      'organization_id': org,
      'kind': 'seat',
      'key': 'clinico',
      'quantity': 5,
      'status': 'active',
      'source': 'stripe',
    });
    // Pero el derecho del módulo clínico está cancelado.
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-mod',
      'organization_id': org,
      'kind': 'module',
      'key': 'clinico',
      'status': 'canceled',
      'source': 'stripe',
    });

    final rows = moduleLicenseRows(repo, org);

    // module:clinico es la primera fila del grupo.
    expect(rows.first.key, 'clinico');

    final clin = rows.firstWhere((r) => r.key == 'clinico');
    expect(clin.hasRight, isFalse); // canceled ≠ active
    expect(clin.switchOn, isTrue); // hay asientos → "encendido"
    expect(clin.agreement.kind, ModuleAgreementCase.onWithoutRight);
    // Copy propio de Clínico: habla de ASIENTOS, no de interruptor.
    expect(clin.agreement.message,
        'Con asientos activos pero sin el derecho clínico: nadie ve el expediente.');
    expect(clin.agreement.message.toLowerCase(), contains('asiento'));
    expect(clin.agreement.message.toLowerCase(), isNot(contains('interruptor')));
  });

  test('seat:clinico activo + module:clinico activo → normal (no rojo falso)',
      () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'clic-ok-org';
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-seat',
      'organization_id': org,
      'kind': 'seat',
      'key': 'clinico',
      'quantity': 5,
      'status': 'active',
      'source': 'stripe',
    });
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-mod',
      'organization_id': org,
      'kind': 'module',
      'key': 'clinico',
      'status': 'active',
      'source': 'stripe',
    });

    final clin =
        moduleLicenseRows(repo, org).firstWhere((r) => r.key == 'clinico');
    expect(clin.agreement.kind, ModuleAgreementCase.normal);
  });
}
