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

  // (a) Coherencia: un seat:clinico ACTIVO con cantidad 0 no habilita nada, y las
  // dos tablas lo dicen igual. hasAsientos (Asientos) == switchOn de Clínico (Módulos).
  Future<(SeatLicenseRow, ModuleLicenseRow)> clinRows(
      LocalStore store, DataRepository repo, String org, int qty) async {
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-seat',
      'organization_id': org,
      'kind': 'seat',
      'key': 'clinico',
      'quantity': qty,
      'status': 'active',
      'source': 'stripe',
    });
    final seat =
        seatLicenseRows(repo, org).firstWhere((r) => r.key == 'clinico');
    final mod =
        moduleLicenseRows(repo, org).firstWhere((r) => r.key == 'clinico');
    return (seat, mod);
  }

  test('(a) cantidad 0 → Asientos ámbar y coincide con Módulos (ambos sin asientos)',
      () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    final (seat, mod) = await clinRows(store, repo, 'coh-0-org', 0);
    // Asientos: derecho activo pero cantidad 0 → ámbar "Derecho sin asientos".
    expect(seat.agreement.kind, ModuleAgreementCase.rightOff);
    expect(seat.hasAsientos, isFalse);
    // Coincide con Módulos: el interruptor derivado del Clínico también es false.
    expect(mod.switchOn, isFalse);
    expect(seat.hasAsientos, mod.switchOn);
  });

  test('(a) cantidad ≥1 → Asientos normal y coincide con Módulos (ambos con asientos)',
      () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    final (seat, mod) = await clinRows(store, repo, 'coh-1-org', 3);
    expect(seat.agreement.kind, ModuleAgreementCase.normal);
    expect(seat.hasAsientos, isTrue);
    expect(mod.switchOn, isTrue);
    expect(seat.hasAsientos, mod.switchOn);
  });

  // (b) La fila de Clínico usa un rightOffMessage que habla de asientos.
  test('(b) Clínico con derecho pero sin asientos → ámbar con copy de asientos', () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'clin-rightoff-org';
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-mod',
      'organization_id': org,
      'kind': 'module',
      'key': 'clinico',
      'status': 'active',
      'source': 'master',
      'grant_type': 'cortesia',
      'reason': 'Cortesía de arranque para el piloto',
      'is_permanent': true,
    });
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-seat',
      'organization_id': org,
      'kind': 'seat',
      'key': 'clinico',
      'quantity': 0,
      'status': 'active',
      'source': 'master',
      'grant_type': 'cortesia',
      'reason': 'Cortesía de arranque para el piloto',
      'is_permanent': true,
    });
    final clin =
        moduleLicenseRows(repo, org).firstWhere((r) => r.key == 'clinico');
    expect(clin.agreement.kind, ModuleAgreementCase.rightOff);
    expect(clin.agreement.message,
        'Sin asientos clínicos: nadie puede usar el expediente.');
    expect(clin.agreement.message.toLowerCase(), contains('asiento'));
  });

  // (d) "Desacuerdos" excluye las filas seatDerived (Clínico).
  test('(d) cuenta 2 y no 3: Clínico ámbar (seatDerived) no suma', () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'count-org';
    // Clínico: derecho activo + asientos 0 → rightOff seatDerived.
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-mc', 'organization_id': org, 'kind': 'module', 'key': 'clinico',
      'status': 'active', 'source': 'stripe',
    });
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-sc', 'organization_id': org, 'kind': 'seat', 'key': 'clinico',
      'quantity': 0, 'status': 'active', 'source': 'stripe',
    });
    // Insumos y Comercial: derecho activo + interruptor apagado → rightOff (no seatDerived).
    for (final k in ['insumos', 'comercial']) {
      await store.upsert(Collections.orgEntitlements, {
        'id': '$org-m$k', 'organization_id': org, 'kind': 'module', 'key': k,
        'status': 'active', 'source': 'stripe',
      });
      await store.upsert(Collections.moduleSettings, {
        'id': '$org-ms$k', 'organization_id': org, 'module_key': k,
        'site_id': null, 'profile_id': null, 'enabled': false,
      });
    }
    final rows = moduleLicenseRows(repo, org);
    // Tres filas en desacuerdo (clinico + insumos + comercial), pero la cuenta excluye
    // seatDerived → 2.
    final raw = rows
        .where((r) =>
            r.agreement.kind == ModuleAgreementCase.rightOff ||
            r.agreement.kind == ModuleAgreementCase.onWithoutRight)
        .length;
    expect(raw, 3);
    expect(disagreementCount(rows), 2);
  });
}
