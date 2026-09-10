import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/protocol_product_rule.dart';
import 'package:kuratracker/services/data_repository.dart';

/// §2 del catálogo de insumos: las reglas de protocolo HUÉRFANAS (sin insumo, o
/// apuntando a uno que no está en el centro) se REPORTAN, no se descartan en
/// silencio como en resolveProtocolProducts. Es lo que hace visible una siembra a
/// medias o un error de clasificación.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('orphanProtocolRules reporta las sin insumo y las que apuntan a uno ausente',
      () async {
    final repo = await DataRepository.instance();
    const org = 'org-test-orphans';
    const site = 'site-test-orphans';

    // Un insumo real del centro/sitio, para la regla que SÍ resuelve.
    final item = await repo.addInventoryItem(
        organizationId: org, siteId: site, name: 'Apósito espuma 10x10');

    // Regla OK (apunta al insumo existente).
    await repo.saveProtocolProductRule(const ProtocolProductRule(
        id: 'r-ok', organizationId: org, category: 'aposito')
        .copyWithItem(item.id));
    // Regla huérfana A: sin insumo.
    await repo.saveProtocolProductRule(const ProtocolProductRule(
        id: 'r-null', organizationId: org, category: 'antimicrobiano'));
    // Regla huérfana B: apunta a un insumo que no está en el centro.
    await repo.saveProtocolProductRule(const ProtocolProductRule(
            id: 'r-missing', organizationId: org, category: 'limpieza')
        .copyWithItem('inexistente-xyz'));

    final orphans = repo.orphanProtocolRules(organizationId: org);
    final ids = orphans.map((o) => o.rule.id).toSet();
    expect(ids, containsAll(<String>{'r-null', 'r-missing'}));
    expect(ids.contains('r-ok'), isFalse);
    expect(
        orphans.firstWhere((o) => o.rule.id == 'r-null').reason,
        contains('sin insumo'));
  });
}

/// Helper de test: clona una regla con un inventory_item_id concreto.
extension on ProtocolProductRule {
  ProtocolProductRule copyWithItem(String? itemId) => ProtocolProductRule(
        id: id,
        organizationId: organizationId,
        category: category,
        inventoryItemId: itemId,
      );
}
