import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// Regresión ff201e7 (retirar SEAT_REQUIRES_ADMIN_MODULE) + su cierre (0128):
/// un administrativo PURO que no cabe en los cupos incluidos consume un asiento
/// CLÍNICO, y la DEMANDA debe contarlo. licenseSummaryFor es el espejo en la app del
/// invariante del servidor (consumed_seat_demand / assert_seat_available):
///   demanda = consumed_clinical_seats + max(0, consumed_admin_slots − incluidos)
///   incluidos = 3 con module:admin, 0 sin él.
/// La rama SQL (rechazo con SEAT_NO_CLINICAL) se verifica aparte con begin…rollback
/// contra el sandbox; aquí se fija el conteo, que es lo que faltaba en test/.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  var seq = 0;

  Future<void> addMember(LocalStore store, String org, List<String> roles,
      {bool active = true, bool exempt = false}) async {
    final pid = 'sd-p-${seq++}';
    await store.upsert(Collections.profiles, {
      'id': pid,
      'role': roles.first,
      'roles': roles,
      'full_name': 'U-$pid',
      'email': '$pid@t.mx',
      'is_active': active,
      'organization_id': org,
    });
    await store.upsert(Collections.userCenterMemberships, {
      'id': 'sd-m-$pid',
      'profile_id': pid,
      'organization_id': org,
      'role': roles.first,
      'roles': roles,
      'is_active': active,
      'seat_exempt': exempt,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> seatClinico(LocalStore store, String org, int qty) =>
      store.upsert(Collections.orgEntitlements, {
        'id': '$org-seat-clinico',
        'organization_id': org,
        'kind': 'seat',
        'key': 'clinico',
        'quantity': qty,
        'status': 'active',
        'source': 'master',
      });

  Future<void> moduleAdmin(LocalStore store, String org) =>
      store.upsert(Collections.orgEntitlements, {
        'id': '$org-module-admin',
        'organization_id': org,
        'kind': 'module',
        'key': 'admin',
        'status': 'active',
        'source': 'master',
      });

  test('(a) repro ff201e7: seat:clinico=2, sin module:admin — el admin puro '
      'desbordado cuenta como demanda clínica → el 3.º alta no cabe', () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'sd-org-a';
    await seatClinico(store, org, 2);
    await addMember(store, org, ['clinico']); // 1 clínico
    await addMember(store, org, ['admin']); //   1 solo-administrativo (desborda)

    final s = repo.licenseSummaryFor(org);
    // Antes del arreglo, clinicalSeats.used era 1 (el admin no se contaba) y quedaba
    // "1 disponible", dejando pasar un 2.º clínico → 3 personas en 2 asientos.
    expect(s.adminSeatOverflow, 1, reason: 'el admin sin cupo desborda');
    expect(s.clinicalSeats.used, 2, reason: 'demanda = 1 clínico + 1 admin desbordado');
    expect(s.clinicalSeats.contracted, 2);
    expect(s.clinicalSeats.full, isTrue,
        reason: 'sin asiento libre: un 3.º alta (SEAT_NO_CLINICAL) no cabe');
  });

  test('(b) con module:admin: 3 administrativos NO consumen asiento clínico; el 4.º '
      'sí (desborda los 3 cupos incluidos)', () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'sd-org-b';
    await seatClinico(store, org, 5);
    await moduleAdmin(store, org);
    for (var i = 0; i < 3; i++) {
      await addMember(store, org, ['admin']);
    }

    final s3 = repo.licenseSummaryFor(org);
    expect(s3.adminSlots.used, 3);
    expect(s3.adminSlots.contracted, 3);
    expect(s3.adminSeatOverflow, 0, reason: 'los 3 caben en los cupos incluidos');
    expect(s3.clinicalSeats.used, 0, reason: 'ninguno consume asiento clínico');

    // El 4.º administrativo desborda → consume un asiento clínico.
    await addMember(store, org, ['admin']);
    final s4 = repo.licenseSummaryFor(org);
    expect(s4.adminSlots.used, 4);
    expect(s4.adminSeatOverflow, 1);
    expect(s4.clinicalSeats.used, 1, reason: 'el 4.º cuenta como demanda clínica');
  });

  test('(c) multi-rol (clínico+admin) consume UN asiento clínico, no cupo admin',
      () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'sd-org-c';
    await seatClinico(store, org, 5);
    await moduleAdmin(store, org);
    await addMember(store, org, ['clinico', 'admin']);

    final s = repo.licenseSummaryFor(org);
    expect(s.clinicalSeats.used, 1, reason: 'consume asiento clínico');
    expect(s.adminSlots.used, 0, reason: 'no ocupa cupo admin aunque sea admin');
    expect(s.adminSeatOverflow, 0);
  });

  test('miembro inactivo o exento no cuenta en la demanda', () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'sd-org-d';
    await seatClinico(store, org, 2);
    await addMember(store, org, ['admin'], active: false); // inactivo
    await addMember(store, org, ['admin'], exempt: true); //  exento

    final s = repo.licenseSummaryFor(org);
    expect(s.adminSlots.used, 0);
    expect(s.adminSeatOverflow, 0);
    expect(s.clinicalSeats.used, 0);
  });
}
