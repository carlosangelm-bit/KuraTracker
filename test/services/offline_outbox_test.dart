// Cola offline (Fase 1): persiste escrituras pendientes y las recupera tras
// recargar la app, mantiene el contador de pendientes y permite drenarlas.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/services/offline/offline_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

OutboxOp _op(String id, {String type = 'insert', String collection = 'wounds'}) =>
    OutboxOp(
      opId: 'op-$id',
      collection: collection,
      type: type,
      rowId: id,
      payload: {'id': id, 'etiology': 'vascular'},
      createdAt: '2026-01-01T00:00:00.000Z',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('encolar aumenta pendientes y persiste entre recargas', () async {
    final box = await OfflineOutbox.load();
    expect(box.length, 0);
    expect(box.pendingCount.value, 0);

    await box.enqueue(_op('w1'));
    await box.enqueue(_op('w2', type: 'update'));
    expect(box.length, 2);
    expect(box.pendingCount.value, 2);

    // Otra "recarga" de la app lee la misma cola persistida.
    final reloaded = await OfflineOutbox.load();
    expect(reloaded.length, 2);
    expect(reloaded.all().map((o) => o.rowId), ['w1', 'w2']);
    expect(reloaded.all().first.type, 'insert');
    expect(reloaded.all()[1].type, 'update');
  });

  test('remover una operación la quita de la cola y baja el contador', () async {
    final box = await OfflineOutbox.load();
    await box.enqueue(_op('w1'));
    await box.enqueue(_op('w2'));

    await box.remove('op-w1');
    expect(box.length, 1);
    expect(box.pendingCount.value, 1);
    expect(box.all().single.rowId, 'w2');

    // Persistido: una recarga solo ve la que queda.
    final reloaded = await OfflineOutbox.load();
    expect(reloaded.all().single.rowId, 'w2');
  });

  test('markFailed incrementa intentos y guarda el error (parking)', () async {
    final box = await OfflineOutbox.load();
    await box.enqueue(_op('w1'));
    await box.markFailed('op-w1', 'RLS denied');

    final reloaded = await OfflineOutbox.load();
    expect(reloaded.all().single.attempts, 1);
    expect(reloaded.all().single.lastError, 'RLS denied');
  });

  test('una cola corrupta en storage se descarta sin romper', () async {
    SharedPreferences.setMockInitialValues({'offline_outbox_v1': 'no-json{{'});
    final box = await OfflineOutbox.load();
    expect(box.length, 0);
  });
}
