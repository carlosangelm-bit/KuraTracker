// Cola de FOTOS offline (Fase 2): persiste bytes + metadatos en sembast
// (memoria en tests, IndexedDB en Web) y los recupera para subirlos al
// reconectar.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/services/offline/photo_outbox.dart';
import 'package:sembast/sembast_memory.dart';

PendingPhoto _photo(String id) => PendingPhoto(
      localId: id,
      fileName: '$id.jpg',
      contentType: 'image/jpeg',
      bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
      meta: {
        'wound_id': 'w1',
        'consultation_id': 'c1',
        'measurement_id': 'm1',
        'photo_stage': 'con_medicion',
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // La factory en memoria persiste por proceso: se limpia entre tests.
  setUp(() => databaseFactoryMemory.deleteDatabase('kura_offline_photos.db'));

  test('encolar guarda bytes+meta y se recuperan tras reabrir', () async {
    final box = await PhotoOutbox.open();
    expect(box.length, 0);

    await box.enqueue(_photo('p1'), createdAt: '2026-01-01T00:00:00.000Z');
    await box.enqueue(_photo('p2'), createdAt: '2026-01-01T00:01:00.000Z');
    expect(box.pendingCount.value, 2);

    // "Reabrir" la app: misma cola persistida en IndexedDB/memoria.
    final reopened = await PhotoOutbox.open();
    final all = await reopened.all();
    expect(all.map((p) => p.localId), ['p1', 'p2']); // orden por created_at
    expect(all.first.bytes, [1, 2, 3, 4, 5]);
    expect(all.first.fileName, 'p1.jpg');
    expect(all.first.meta['wound_id'], 'w1');
    expect(all.first.meta['measurement_id'], 'm1');
  });

  test('remover una foto baja el contador y la quita', () async {
    final box = await PhotoOutbox.open();
    await box.enqueue(_photo('p1'), createdAt: '2026-01-01T00:00:00.000Z');
    await box.enqueue(_photo('p2'), createdAt: '2026-01-01T00:01:00.000Z');

    await box.remove('p1');
    expect(box.pendingCount.value, 1);

    final reopened = await PhotoOutbox.open();
    final all = await reopened.all();
    expect(all.single.localId, 'p2');
  });
}
