// Red de seguridad del hidratado por tandas: refreshCollection TRAGA el error como
// resiliencia (un desfase en UNA tabla no debe tumbar el login), pero eso vuelve un
// FALLO indistinguible de "vacío de verdad". Estas pruebas clavan la distinción a
// nivel de datos —lo único no-testeable es el letrero en pantalla—: sin ellas, el
// candado se cae en el próximo refactor sin que nadie se entere, que es justo el
// defecto que vino a arreglar.
//
// Truco (mismo patrón que _RpcSpyStore en resolve_protocol_demo_test): una subclase
// de SupabaseDataStore que sobreescribe el seam de red fetchCollectionRows para
// FALLAR una colección concreta, sin tocar la red. Así se ejercita el manejo REAL
// de fallo de refreshCollection.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kuratracker/services/local_db/local_store.dart' show Collections;
import 'package:kuratracker/services/remote/supabase_data_store.dart';

class _FailingStore extends SupabaseDataStore {
  _FailingStore(this.failCollection)
      : super(SupabaseClient('http://localhost', 'test-anon-key'));
  final String failCollection;

  @override
  Future<List<Map<String, dynamic>>> fetchCollectionRows(
      String collection) async {
    if (collection == failCollection) {
      throw Exception('fallo simulado (red/permiso/esquema) en $collection');
    }
    return const []; // el resto "carga" vacío, con éxito
  }
}

void main() {
  test('un fallo NO se disfraza de vacío: loadFailed=true y la caché previa queda '
      'INTACTA (no se pisa con [])', () async {
    final store = _FailingStore(Collections.productCatalog);
    // Carga PREVIA exitosa simulada (respaldo en caché, como tras una hidratación
    // anterior que sí trajo los 137 productos de prod).
    store.primeCache({
      Collections.productCatalog: [
        {'id': 'p1', 'title': 'Apósito X', 'is_active': true},
      ],
    });
    expect(store.loadFailed(Collections.productCatalog), isFalse,
        reason: 'baseline: antes del fallo no está marcada');

    await store.refreshCollection(Collections.productCatalog);

    expect(store.loadFailed(Collections.productCatalog), isTrue,
        reason: 'el fallo queda MARCADO para que la lectura lo distinga de vacío');
    expect(store.getAll(Collections.productCatalog), isNotEmpty,
        reason: 'la caché previa NO se pisó con []');
    expect(store.getAll(Collections.productCatalog).first['id'], 'p1',
        reason: 'getAll devuelve lo PREVIO (respaldo), no vacío');
  });

  test('vacío-de-verdad y fallo SON distinguibles: sin caché previa, getAll da [] '
      'pero loadFailed lo delata', () async {
    final store = _FailingStore(Collections.productCatalog);
    await store.refreshCollection(Collections.productCatalog);
    expect(store.getAll(Collections.productCatalog), isEmpty);
    expect(store.loadFailed(Collections.productCatalog), isTrue,
        reason: 'no es vacío legítimo: falló, y hay que poder saberlo');
  });

  test('una carga EXITOSA limpia la marca de fallo (vacío legítimo)', () async {
    final store = _FailingStore('otra_coleccion'); // productCatalog NO falla
    await store.refreshCollection(Collections.productCatalog); // devuelve []
    expect(store.getAll(Collections.productCatalog), isEmpty);
    expect(store.loadFailed(Collections.productCatalog), isFalse,
        reason: 'cargó bien y está vacío DE VERDAD: no marcado');
  });
}
