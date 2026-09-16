// §15 etapa 6.2 — capa de LECTURA de la Matriz de dos fuentes. Verifica que el catálogo Kura+
// (global, sin organization_id) se lee y modela bien, que hasIdentity distingue atada de huérfana
// con nombre, y que el gating de author (module:protocol:author vigente) decide el modo catálogo.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart' show Collections;
import 'package:kuratracker/services/remote/data_store.dart';

class _MemStore implements DataStore {
  final Map<String, List<Map<String, dynamic>>> data;
  _MemStore(this.data);
  @override
  List<Map<String, dynamic>> getAll(String c) => data[c] ?? const [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('MemStore: ${i.memberName}');
}

const _authorOrg = '11111111-1111-1111-1111-111111111111';
const _plainOrg = '22222222-2222-2222-2222-222222222222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DataRepository> repo() => DataRepository.forSeeding(_MemStore({
        // Catálogo GLOBAL: sin organization_id. Una regla ATADA (par shopify) y una HUÉRFANA.
        Collections.protocolCatalogRules: [
          {
            'id': 'cat-1',
            'category': 'aposito',
            'context_kind': 'etiologia',
            'context_value': 'lpp',
            'name': 'Mepilex® Border Flex',
            'brand': 'Mölnlycke',
            'scale_label': 'Braden — prevención',
            'sort_order': 1,
            'shopify_product_id': 'SP-1',
            'shopify_variant_id': '',
          },
          {
            'id': 'cat-2',
            'category': 'aposito',
            'context_kind': 'etiologia',
            'context_value': 'quemaduras',
            'name': 'Exufiber®', // sin identidad → huérfana con nombre
            'brand': 'Mölnlycke',
            'sort_order': 0,
          },
        ],
        Collections.orgEntitlements: [
          {
            'organization_id': _authorOrg,
            'kind': 'module',
            'key': 'protocol:author',
            'status': 'active',
            'source': 'master',
            'current_period_end': null,
          },
        ],
      }));

  test('listProtocolCatalogRules lee el catálogo global, ordenado por (categoría, sort_order)',
      () async {
    final r = await repo();
    final rules = r.listProtocolCatalogRules();
    expect(rules.length, 2);
    // sort_order 0 antes que 1:
    expect(rules.first.id, 'cat-2');
    expect(rules.last.id, 'cat-1');
    // prosa + contexto + etiqueta se modelan:
    expect(rules.last.name, 'Mepilex® Border Flex');
    expect(rules.last.contextValue, 'lpp');
    expect(rules.last.scaleLabel, 'Braden — prevención');
    // global → sin organization_id:
    expect(rules.first.organizationId, '');
  });

  test('hasIdentity distingue atada de huérfana con nombre', () async {
    final r = await repo();
    final byId = {for (final x in r.listProtocolCatalogRules()) x.id: x};
    expect(byId['cat-1']!.hasIdentity, isTrue); // tiene par shopify
    expect(byId['cat-2']!.hasIdentity, isFalse); // huérfana con nombre
  });

  test('canAuthorProtocolCatalog = AUTORIDAD (rol + derecho), no solo capacidad', () async {
    final r = await repo();
    // admin del centro author → autoría.
    expect(
        r.canAuthorProtocolCatalog(
            organizationId: _authorOrg, isAdmin: true, isMaster: false),
        isTrue);
    // MISMO centro (tiene el derecho) pero SIN rol admin → NO autoría (el tablero mudo cerrado).
    expect(
        r.canAuthorProtocolCatalog(
            organizationId: _authorOrg, isAdmin: false, isMaster: false),
        isFalse,
        reason: 'capacidad del centro sin rol no basta — debe coincidir con la RLS');
    // admin pero centro SIN el derecho → NO autoría.
    expect(
        r.canAuthorProtocolCatalog(
            organizationId: _plainOrg, isAdmin: true, isMaster: false),
        isFalse);
    // master → autoría siempre.
    expect(
        r.canAuthorProtocolCatalog(
            organizationId: _plainOrg, isAdmin: false, isMaster: true),
        isTrue);
  });
}
