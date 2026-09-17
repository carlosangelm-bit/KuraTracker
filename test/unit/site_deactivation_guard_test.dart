// Guardia Dart de setSiteActive (Admin del centro — Sitios, §5): desactivar un sitio
// se rechaza en tres casos, con el MISMO mensaje que el trigger 0134
// (trg_zz_prevent_site_deactivation). Y el caso positivo: un sitio que no cae en
// ninguno de los tres SÍ se desactiva —una guardia que bloquea todo también "pasaría"
// los tres rechazos—.
//
// Local: data_repository no arrastra google_fonts. Verificado en rojo quitando la
// guardia (vuelve a las dos líneas que solo escriben is_active).
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';
import 'package:kuratracker/services/remote/data_store.dart';

/// Store en memoria: la guardia solo usa getAll + updateRow.
class _MemStore implements DataStore {
  final Map<String, List<Map<String, dynamic>>> data;
  _MemStore(this.data);

  @override
  List<Map<String, dynamic>> getAll(String collection) =>
      data[collection] ?? const [];

  @override
  Future<Map<String, dynamic>> updateRow(
      String collection, String id, Map<String, dynamic> patch) async {
    final row = data[collection]!.firstWhere((r) => r['id'] == id);
    row.addAll(patch);
    return row;
  }

  @override
  Future<Map<String, dynamic>> insertRow(
      String collection, Map<String, dynamic> d) async {
    (data[collection] ??= []).add(d);
    return d;
  }

  @override
  Future<Map<String, dynamic>> upsertRow(
          String collection, Map<String, dynamic> d) async =>
      insertRow(collection, d);

  @override
  Future<void> deleteRow(String collection, String id) async =>
      data[collection]?.removeWhere((r) => r['id'] == id);

  @override
  Future<void> refreshCollection(String collection) async {}

  @override
  Future<void> hydrate({bool force = false}) async {}
}

Map<String, dynamic> _site(String id,
        {bool active = true, String org = 'org'}) =>
    {
      'id': id,
      'name': 'Sitio $id',
      'kind': 'clinica',
      'is_active': active,
      'organization_id': org,
    };

Map<String, dynamic> _staff(String id, String siteId,
        {bool active = true, String org = 'org'}) =>
    {
      'id': id,
      'folio': 'K2026-0001',
      'full_name': 'Ana Ruiz',
      'role_title': 'Especialista',
      'primary_site_id': siteId,
      'is_active': active,
      'organization_id': org,
      'created_at': '2026-01-01T00:00:00.000Z',
    };

Map<String, dynamic> _move(String id, String siteId, int delta,
        {String item = 'it1', String org = 'org'}) =>
    {
      'id': id,
      'organization_id': org,
      'site_id': siteId,
      'inventory_item_id': item,
      'delta': delta,
      'reason': 'ajuste',
      'created_at': '2026-01-01T00:00:00.000Z',
    };

Future<DataRepository> _repo(Map<String, List<Map<String, dynamic>>> d) =>
    DataRepository.forSeeding(_MemStore(d));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rechazo 1: es el único sitio activo del centro', () async {
    final repo = await _repo({
      Collections.sites: [_site('s1')],
    });
    expect(
      () => repo.setSiteActive('s1', false),
      throwsA(predicate((e) => e.toString().contains(
          'es el único activo del centro y toda consulta necesita un sitio. '
          'Da de alta otro antes de desactivar este.'))),
    );
  });

  test('rechazo 2: tiene personal activo con este sitio como principal', () async {
    final repo = await _repo({
      Collections.sites: [_site('s1'), _site('s2')], // s2 evita el rechazo 1
      Collections.staff: [_staff('p1', 's1')],
    });
    expect(
      () => repo.setSiteActive('s1', false),
      throwsA(predicate((e) => e.toString().contains(
          '1 personas lo tienen como sitio principal. Reasígnalas en Personal '
          'antes de desactivarlo.'))),
    );
  });

  test('rechazo 3: tiene existencias de inventario distintas de cero', () async {
    final repo = await _repo({
      Collections.sites: [_site('s1'), _site('s2')],
      Collections.inventoryMovements: [_move('m1', 's1', 5)],
    });
    expect(
      () => repo.setSiteActive('s1', false),
      throwsA(predicate((e) => e.toString().contains(
          'tiene existencias en inventario. Trasládalas o ajústalas a cero antes.'))),
    );
  });

  test('caso positivo: un sitio sin ninguno de los tres SÍ se desactiva', () async {
    final store = _MemStore({
      Collections.sites: [_site('s1'), _site('s2')],
      Collections.staff: [_staff('p1', 's2')], // apunta a OTRO sitio
      Collections.inventoryMovements: [
        _move('m1', 's1', 5),
        _move('m2', 's1', -5), // neto 0 → no bloquea
      ],
    });
    final repo = await DataRepository.forSeeding(store);
    await repo.setSiteActive('s1', false); // no lanza
    final s1 = store.data[Collections.sites]!.firstWhere((r) => r['id'] == 's1');
    expect(s1['is_active'], isFalse, reason: 'debió escribirse is_active=false');
  });
}
