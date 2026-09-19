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
import 'package:kuratracker/models/protocol_product_rule.dart' show kRegimenSourceUnknown;
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
  // includeSource:false simula una migración futura que redefine resolve_protocol SIN la columna
  // source — el defecto de contrato que el centinela 'desconocido' debe hacer visible.
  _RpcSpyStore({this.includeSource = true})
      : super(SupabaseClient('http://localhost', 'test-anon-key'));
  final bool includeSource;
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
        if (includeSource) 'source': 'kura',
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

  // EL IMPORTE (19-sep): el precio se enriquece en Dart por inventory_item_id; 0149 quitó el filtro
  // de sitio en el SQL pero el enriquecimiento seguía filtrando por sitio, así que un insumo
  // resuelto en OTRO sitio del centro (p. ej. Almacén) llegaba SIN precio y el renglón/cobro nacía
  // en $0. GUARDA de la cadena completa (regla→resolución→renglón→importe): el precio debe llegar
  // aunque el insumo viva en un sitio distinto del que se pasa. Si alguien repone el filtro de
  // sitio en el enriquecimiento, esto se pone rojo.
  test('el precio se enriquece aunque el insumo viva en OTRO sitio del centro', () async {
    final spy = _RpcSpyStore(); // devuelve inventory_item_id: rpc-item-id
    spy.primeCache({
      Collections.inventoryItems: [
        {
          'id': 'rpc-item-id', 'organization_id': org, 'site_id': 'almacen',
          'name': 'Mepilex', 'unit_price': 337, 'unit_cost': 10,
          'currency': 'MXN', 'is_active': true,
        }
      ],
      Collections.protocolProductRules: const [],
    });
    final repo = await DataRepository.forSeeding(spy);
    // La consulta pasa OTRO sitio (consultorio-1); el insumo vive en almacen.
    final out = await repo.resolveProtocolProductsRpc(
        organizationId: org, categories: {_tag('aposito')}, siteId: 'consultorio-1');
    expect(out.single.inventoryItemId, 'rpc-item-id');
    expect(out.single.unitPrice, 337,
        reason: 'si el enriquecimiento vuelve a filtrar por sitio, el insumo de otro sitio '
            'queda sin precio y el cobro nace en \$0');
    expect(out.single.unitCost, 10);
  });

  test('FUENTE 6.1 · el resolvedor de demo (reglas propias) emite propio', () async {
    final repo = await DataRepository.forSeeding(_MemStore(seedFromCorpus()));
    final out = await repo.resolveProtocolProductsRpc(
      organizationId: org, categories: {_tag('aposito')}, siteId: site, areaCm2: 5);
    expect(out, isNotEmpty);
    expect(out.every((r) => r.source == 'propio'), isTrue,
        reason: 'la demo resuelve reglas propias → source propio');
  });

  // Sin default inocente: si el RPC no trae la columna (contrato roto), NO se inventa 'propio'
  // —eso etiquetaría el catálogo como régimen propio, verde y mintiendo—. Se marca 'desconocido'.
  test('FUENTE 6.1 · source ausente en el RPC → desconocido, no propio', () async {
    final spy = _RpcSpyStore(includeSource: false);
    spy.primeCache({
      Collections.inventoryItems: const [],
      Collections.protocolProductRules: const [],
    });
    final repo = await DataRepository.forSeeding(spy);
    final out = await repo.resolveProtocolProductsRpc(
      organizationId: org, categories: {_tag('aposito')}, siteId: site);
    expect(out.single.source, kRegimenSourceUnknown,
        reason: 'columna ausente = defecto de contrato, no el valor más inocente');
  });

  // FRASE (§1 hilo de la nota): la FRASE de la regla (note_phrase) llega al resuelto para que
  // el clínico pueda insertarla en la nota. resolve_protocol la devuelve; antes Dart la tiraba.
  test('note_phrase de la regla llega al ResolvedProtocolProduct (demo)', () async {
    final repo = await DataRepository.forSeeding(_MemStore({
      Collections.inventoryItems: [
        {
          'id': 'item-frase',
          'organization_id': org,
          'site_id': site,
          'name': 'Apósito de espuma',
          'unit_cost': 10.0,
          'currency': 'MXN',
          'is_active': true,
        }
      ],
      Collections.protocolProductRules: [
        {
          'id': 'rule-frase',
          'organization_id': org,
          'category': 'aposito',
          'inventory_item_id': 'item-frase',
          'name': 'Apósito de espuma',
          'dimension': 'none',
          'quantity_mode': 'fixed',
          'quantity_value': 1,
          'sort_order': 0,
          'exudate_levels': const [],
          'zone_groups': const [],
          'infection': 'any',
          'priority': 0,
          'note_phrase': 'Cambiar cada 72 h; vigilar exudado.',
        }
      ],
    }));
    final out = await repo.resolveProtocolProductsRpc(
        organizationId: org, categories: {_tag('aposito')}, siteId: site, areaCm2: 5);
    expect(out, isNotEmpty);
    expect(out.single.notePhrase, 'Cambiar cada 72 h; vigilar exudado.',
        reason: 'la frase para la nota debe viajar hasta el resuelto');
  });

  // ESPEJO del SQL 0150 (regresión del left join): en la misma categoría, una regla ATADA menos
  // específica gana sobre una huérfana (insumo en otro centro) MÁS específica. Sin "preferir
  // atada", el clínico se quedaría con un nombre sin insumo usable.
  test('demo: estar atada manda sobre ser específica (no la desplaza una huérfana)', () async {
    const orgA = '99999999-9999-9999-9999-999999999999';
    const orgB = '88888888-8888-8888-8888-888888888888';
    final repo = await DataRepository.forSeeding(_MemStore({
      Collections.inventoryItems: [
        // insumo del centro A (atado). site_id no filtra (0149), pero el modelo lo exige.
        {'id': 'it-real', 'organization_id': orgA, 'site_id': 's-a',
         'name': 'Venda-REAL', 'unit_cost': 1.0, 'currency': 'MXN', 'is_active': true},
        // insumo que vive en OTRO centro (B): existe, pero no está en A
        {'id': 'it-otro', 'organization_id': orgB, 'site_id': 's-b',
         'name': 'Venda-otro-centro', 'unit_cost': 1.0, 'currency': 'MXN', 'is_active': true},
      ],
      Collections.protocolProductRules: [
        // atada, GENÉRICA (spec 0)
        {'id': 'r-atada', 'organization_id': orgA, 'category': 'aposito',
         'inventory_item_id': 'it-real', 'name': 'Venda-atada', 'dimension': 'none',
         'quantity_mode': 'fixed', 'quantity_value': 1, 'sort_order': 0,
         'exudate_levels': const [], 'zone_groups': const [], 'infection': 'any', 'priority': 0},
        // NO atada (insumo en B), MÁS ESPECÍFICA (area + exudado, spec 2)
        {'id': 'r-esp', 'organization_id': orgA, 'category': 'aposito',
         'inventory_item_id': 'it-otro', 'name': 'Venda-especifica', 'dimension': 'area',
         'min_value': 0, 'max_value': 100, 'quantity_mode': 'fixed', 'quantity_value': 1,
         'sort_order': 1, 'exudate_levels': const ['moderado'], 'zone_groups': const [],
         'infection': 'any', 'priority': 0},
      ],
    }));
    final out = await repo.resolveProtocolProductsRpc(
        organizationId: orgA, categories: {_tag('aposito')},
        areaCm2: 5, exudateLevel: 'moderado');
    expect(out.length, 1);
    expect(out.single.inventoryItemId, 'it-real',
        reason: 'gana la ATADA; la huérfana más específica no debe desplazarla');
    expect(out.single.name, 'Venda-REAL');
  });
}
