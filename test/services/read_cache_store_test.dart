// Caché de lectura persistente (Fase 3): guarda las filas por colección en
// sembast (memoria en tests / IndexedDB en Web) y las recupera para ver
// expedientes sin señal; se borra en logout.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/services/offline/read_cache_store.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => databaseFactoryMemory.deleteDatabase('kura_read_cache.db'));

  test('saveAll → loadAll recupera las colecciones tras reabrir', () async {
    final rc = await ReadCacheStore.open();
    await rc.saveAll({
      'patients': [
        {'id': 'p1', 'full_name': 'Ana'},
        {'id': 'p2', 'full_name': 'Luis'},
      ],
      'wounds': [
        {'id': 'w1', 'patient_id': 'p1', 'etiology': 'vascular'},
      ],
    });

    // "Reabrir" la app offline: se lee la misma caché persistida.
    final reopened = await ReadCacheStore.open();
    final all = await reopened.loadAll();
    expect(all.keys.toSet(), {'patients', 'wounds'});
    expect(all['patients']!.length, 2);
    expect(all['patients']!.first['full_name'], 'Ana');
    expect(all['wounds']!.single['etiology'], 'vascular');
  });

  test('saveCollection actualiza una sola colección', () async {
    final rc = await ReadCacheStore.open();
    await rc.saveCollection('patients', [
      {'id': 'p1', 'full_name': 'Ana'},
    ]);
    await rc.saveCollection('patients', [
      {'id': 'p1', 'full_name': 'Ana'},
      {'id': 'p2', 'full_name': 'Luis'},
    ]);
    final all = await (await ReadCacheStore.open()).loadAll();
    expect(all['patients']!.length, 2);
  });

  test('clear borra toda la caché (logout)', () async {
    final rc = await ReadCacheStore.open();
    await rc.saveCollection('patients', [
      {'id': 'p1'}
    ]);
    await rc.clear();
    final all = await (await ReadCacheStore.open()).loadAll();
    expect(all, isEmpty);
  });
}
