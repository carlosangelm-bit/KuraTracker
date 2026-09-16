// Pruebas del resolvedor LOCAL DE DEMO (_resolveProtocolLocalDemo) — §15 etapa 3.5.
//
// Dos condiciones que puso Carlos al aprobar el camino B (resolver en local SOLO en demo):
//
//  CONDICIÓN 1 — UN SOLO corpus, literalmente el mismo archivo. El test de conducta del
//  SERVIDOR (supabase/tests/local/resolve_protocol_behavior.sql) y este test leen el MISMO
//  supabase/tests/protocol_behavior_corpus.json. Si las dos implementaciones divergen, una de
//  las dos pruebas se pone roja. No hay dos copias que puedan separarse en silencio.
//
//  CONDICIÓN 2 — que el camino de demo SIGA siendo solo de la demo. El peligro no es que las
//  dos copias difieran (para eso está el corpus); es que la puerta `_store is! SupabaseDataStore`
//  cambie de sentido y el resolvedor local empiece a correr en producción, con el catálogo Kura+
//  viajando al dispositivo. La prueba de conducta NO lo atraparía (el resultado sería correcto;
//  cambia QUIÉN lo calcula). Por eso el segundo test afirma lo contrario: con un SupabaseDataStore
//  presente, _resolveProtocolLocalDemo es INALCANZABLE — la llamada va a la RPC. Si quitas la
//  puerta, ese test se cae.
//
// Corre bajo `flutter test` (importa el código real de Dart). Sin Docker ni red.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/note_option_catalog.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart' show Collections;
import 'package:kuratracker/services/remote/data_store.dart';
import 'package:kuratracker/services/remote/supabase_data_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Store en memoria: getAll basta para el resolvedor de reglas propias.
class _MemStore implements DataStore {
  final Map<String, List<Map<String, dynamic>>> data;
  _MemStore(this.data);
  @override
  List<Map<String, dynamic>> getAll(String c) => data[c] ?? const [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('MemStore: ${i.memberName}');
}

// SupabaseDataStore de mentira: NO toca la red. Registra la llamada a la RPC y devuelve un
// producto FIJO ('rpc-item-id') distinto del que resolvería el camino local, para poder
// distinguir por el resultado QUIÉN calculó.
class _RpcSpyStore extends SupabaseDataStore {
  _RpcSpyStore() : super(SupabaseClient('http://localhost', 'test-anon-key'));
  int rpcCalls = 0;
  String? lastRpcName;
  @override
  Future<dynamic> callRpcResult(String name, Map<String, dynamic> params) async {
    rpcCalls++;
    lastRpcName = name;
    return <Map<String, dynamic>>[
      {
        'category': 'aposito',
        'inventory_item_id': 'rpc-item-id',
        'name': 'Producto resuelto por el servidor',
        'quantity': 1,
        'source': 'kura',
      }
    ];
  }
}

KuraTag _tag(String dbValue) =>
    KuraTag.values.firstWhere((t) => t.dbValue == dbValue);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final corpus = jsonDecode(
      File('supabase/tests/protocol_behavior_corpus.json').readAsStringSync())
      as Map<String, dynamic>;
  final org = corpus['org'] as String;
  final site = corpus['site'] as String;

  Map<String, List<Map<String, dynamic>>> seedFromCorpus() => {
        Collections.inventoryItems: [
          for (final it in (corpus['items'] as List).cast<Map<String, dynamic>>())
            {
              'id': it['id'],
              'organization_id': org,
              'site_id': it['site'],
              'name': it['name'],
              'unit_cost': 1.0,
              'currency': 'MXN',
              'is_active': true,
            }
        ],
        Collections.protocolProductRules: [
          for (final r in (corpus['rules'] as List).cast<Map<String, dynamic>>())
            {
              'id': r['id'],
              'organization_id': org,
              'category': r['category'],
              'inventory_item_id': r['item'],
              'name': r['name'],
              'dimension': r['dimension'],
              'min_value': r['min'],
              'max_value': r['max'],
              'quantity_mode': r['quantity_mode'],
              'quantity_value': r['quantity_value'],
              'sort_order': r['sort_order'],
              'exudate_levels': r['exudate_levels'],
              'zone_groups': r['zone_groups'],
              'infection': r['infection'],
              'priority': 0,
            }
        ],
      };

  // CONDICIÓN 1 — el resolvedor de demo devuelve EXACTAMENTE lo que el corpus espera (el mismo
  // que verifica el servidor). Un caso por entrada del corpus.
  group('CONDICIÓN 1 · corpus único (demo == servidor)', () {
    late DataRepository repo;
    setUp(() async {
      repo = await DataRepository.forSeeding(_MemStore(seedFromCorpus()));
    });

    for (final c in (corpus['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['label'] as String, () async {
        final out = await repo.resolveProtocolProductsRpc(
          organizationId: org,
          categories: {
            for (final s in (c['categories'] as List).cast<String>()) _tag(s)
          },
          areaCm2: (c['area'] as num?)?.toDouble(),
          volumeCm3: (c['volume'] as num?)?.toDouble(),
          exudateLevel: c['exudate'] as String?,
          zoneGroup: c['zone'] as String?,
          infectionSuspected: c['infection'] as bool?,
          siteId: site,
        );
        // Formato idéntico al del .sql: category|name|qty(3 decimales), en orden.
        final got = out
            .map((r) =>
                '${r.category}|${r.name}|${r.quantity.toStringAsFixed(3)}')
            .join(', ');
        expect(got, c['expected'],
            reason: 'el resolvedor de demo se apartó del corpus en "${c['label']}"');
      });
    }
  });

  // CONDICIÓN 2 — la puerta. Con un SupabaseDataStore presente, _resolveProtocolLocalDemo NO se
  // alcanza: la resolución va a la RPC. Roja si alguien quita/voltea la puerta.
  test('CONDICIÓN 2 · con SupabaseDataStore, el resolvedor local es INALCANZABLE (va a la RPC)',
      () async {
    final spy = _RpcSpyStore();
    // Reglas PROPIAS sembradas que, SI el camino local corriera, ganarían con 'local-item-id'
    // (distinto de lo que devuelve la RPC). Así el resultado delata quién calculó.
    spy.primeCache({
      Collections.inventoryItems: [
        {
          'id': 'local-item-id',
          'organization_id': org,
          'site_id': site,
          'name': 'Producto resuelto en LOCAL',
          'unit_cost': 1.0,
          'currency': 'MXN',
          'is_active': true,
        }
      ],
      Collections.protocolProductRules: [
        {
          'id': 'rule-local',
          'organization_id': org,
          'category': 'aposito',
          'inventory_item_id': 'local-item-id',
          'name': 'Producto resuelto en LOCAL',
          'dimension': 'none',
          'min_value': null,
          'max_value': null,
          'quantity_mode': 'fixed',
          'quantity_value': 1,
          'sort_order': 0,
          'exudate_levels': <String>[],
          'zone_groups': <String>[],
          'infection': 'any',
          'priority': 0,
        }
      ],
    });
    final repo = await DataRepository.forSeeding(spy);

    final out = await repo.resolveProtocolProductsRpc(
      organizationId: org,
      categories: {_tag('aposito')},
      siteId: site,
    );

    // La RPC se llamó (una vez, la función correcta)…
    expect(spy.rpcCalls, 1, reason: 'con Supabase, la resolución DEBE ir a la RPC');
    expect(spy.lastRpcName, 'resolve_protocol');
    // …y el resultado vino de la RPC, NO del resolvedor local (que habría dado 'local-item-id').
    expect(out.single.inventoryItemId, 'rpc-item-id',
        reason: 'el resultado salió del camino local → la puerta de demo se coló a producción');
  });

  // FUENTE (6.1) — la degradación catálogo→propio debe ser OBSERVABLE. source viaja del RPC al
  // modelo; si alguien deja de leer m['source'] en el mapeo, estos tests se ponen rojos y la
  // degradación deja de ser un cambio en silencio.
  test('FUENTE 6.1 · source del RPC llega al modelo (kura)', () async {
    final spy = _RpcSpyStore(); // su callRpcResult devuelve source: 'kura'
    spy.primeCache({
      Collections.inventoryItems: const [],
      Collections.protocolProductRules: const [],
    });
    final repo = await DataRepository.forSeeding(spy);
    final out = await repo.resolveProtocolProductsRpc(
      organizationId: org, categories: {_tag('aposito')}, siteId: site);
    expect(out.single.source, 'kura',
        reason: 'si el mapper deja de leer m[source], la degradación catálogo→propio vuelve a ser invisible');
  });

  test('FUENTE 6.1 · el resolvedor de demo (reglas propias) emite propio', () async {
    final repo = await DataRepository.forSeeding(_MemStore(seedFromCorpus()));
    final out = await repo.resolveProtocolProductsRpc(
      organizationId: org, categories: {_tag('aposito')}, siteId: site, areaCm2: 5);
    expect(out, isNotEmpty);
    expect(out.every((r) => r.source == 'propio'), isTrue,
        reason: 'la demo resuelve reglas propias → source propio');
  });
}
