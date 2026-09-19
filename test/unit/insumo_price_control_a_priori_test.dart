// GUARDA (Carlos, 19-sep): el precio del insumo se controla ANTES del cobro, no en la hoja de cobro.
// La regla ÚNICA vive en lib/core/pricing.dart (resolveSalePrice); TODAS las puertas por las que un
// insumo entra o cambia de precio pasan por ella, para que NINGUNA deje un insumo con costo y sin
// precio de venta (que si no se cobraría A COSTO, en silencio). Las seis puertas:
//   1. alta manual            → addInventoryItem
//   2. edición                → _editItem → updateInventoryItem (rutea por resolveSalePrice)
//   3. CSV alta               → addInventoryItem
//   4. CSV re-subida          → resolveSalePrice + updateInventoryItem
//   5. tienda desde Inventario→ addInventoryItem(unitCost: precioTienda)
//   6. sync Shopify (alta)    → addInventoryItem(unitCost: cat.price)
//   (+ seed demo              → resolveSalePrice(cost:))
//
// Dos partes:
//  A) COMPORTAMIENTO — se ejercitan las cuatro puertas que crean vía addInventoryItem (1,3,5,6 todas
//     entran por ese chokepoint) contra un LocalStore real y se MIRA EL RESULTADO (item.unitPrice):
//     costo>0 ⇒ precio != null, con el default costo/0.75. Prueba de mutación: si resolveSalePrice
//     deja de derivar, o addInventoryItem deja de aplicarla, esto se pone rojo.
//  B) FUENTE — las puertas que NO pasan por addInventoryItem (edición, CSV re-subida, seed demo)
//     deben rutear el precio por la regla. Derivada de la fuente: si una nueva puerta escribe el
//     precio sin la regla —o si reaparece el default legado "costo +30 %" (× 1.3)—, esto se pone rojo.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/core/pricing.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('regla única del precio (pricing.dart)', () {
    test('costo>0 sin precio ⇒ precio derivado (costo / 0.75), NUNCA null', () {
      expect(resolveSalePrice(cost: 100), 133.33); // 100 / 0.75 = 133.333… → 133.33
      expect(defaultSalePriceFromCost(300.0), 400.0); // 300 / 0.75 = 400
      // INVARIANTE central de la spec: ningún costo positivo queda sin precio.
      for (final c in <double>[0.01, 1, 12.5, 99.99, 1000, 123456.78]) {
        expect(resolveSalePrice(cost: c), isNotNull,
            reason: 'costo $c debe producir precio (no dejar el insumo a costo)');
      }
    });

    test('precio capturado gana; sin costo utilizable ⇒ null (sin precio)', () {
      expect(resolveSalePrice(price: 50, cost: 100), 50); // el capturado a mano manda
      expect(resolveSalePrice(price: 50), 50);
      expect(resolveSalePrice(), isNull);
      expect(resolveSalePrice(cost: 0), isNull);
      expect(resolveSalePrice(cost: -5), isNull);
    });
  });

  group('puertas de alta (chokepoint addInventoryItem) — mira el resultado', () {
    late DataRepository repo;
    late String orgId;
    late String siteId;

    setUp(() async {
      repo = await DataRepository.instance();
      final org = repo
          .listOrganizations()
          .firstWhere((o) => repo.listSites(organizationId: o.id).isNotEmpty);
      orgId = org.id;
      siteId = repo.listSites(organizationId: orgId).first.id;
    });

    test('alta con costo y SIN precio ⇒ el insumo queda CON precio derivado', () async {
      final it = await repo.addInventoryItem(
          organizationId: orgId, siteId: siteId, name: 'Guante nitrilo', unitCost: 100);
      expect(it.unitCost, 100);
      expect(it.unitPrice, 133.33);
    });

    test('alta con precio capturado ⇒ ese precio (no se deriva)', () async {
      final it = await repo.addInventoryItem(
          organizationId: orgId,
          siteId: siteId,
          name: 'Gasa estéril',
          unitCost: 100,
          unitPrice: 250);
      expect(it.unitPrice, 250);
    });

    test('tienda desde Inventario / sync Shopify: precio de tienda = COSTO ⇒ precio de venta derivado',
        () async {
      // Ambas puertas llaman addInventoryItem(unitCost: <precio de la tienda>): el precio de Kura+
      // es el COSTO del centro; el precio al paciente lo deriva el default.
      final it = await repo.addInventoryItem(
          organizationId: orgId, siteId: siteId, name: 'Apósito Kura+', unitCost: 80);
      expect(it.unitCost, 80);
      expect(it.unitPrice, isNotNull, reason: 'costo del centro ⇒ precio de venta derivado');
    });

    test('NINGUNA alta con costo positivo deja el insumo sin precio', () async {
      for (final c in <double>[1, 33.33, 500]) {
        final it = await repo.addInventoryItem(
            organizationId: orgId, siteId: siteId, name: 'insumo_$c', unitCost: c);
        final costSinPrecio = (it.unitCost ?? 0) > 0 && it.unitPrice == null;
        expect(costSinPrecio, isFalse,
            reason: 'costo $c quedó sin precio: la puerta de alta se saltó la regla');
      }
    });
  });

  group('puertas que NO pasan por addInventoryItem — derivadas de la fuente', () {
    test('addInventoryItem (chokepoint) computa unit_price por resolveSalePrice', () {
      final src = File('lib/services/data_repository.dart').readAsStringSync();
      final body = _slice(src, 'Future<InventoryItem> addInventoryItem(',
          'return InventoryItem.fromJson(saved);');
      expect(body, isNotEmpty, reason: 'no se encontró el cuerpo de addInventoryItem');
      expect(body.contains('resolveSalePrice(price: unitPrice, cost: unitCost)'), isTrue,
          reason: 'addInventoryItem debe derivar el precio por la regla única');
      expect(RegExp(r"'unit_price':\s*price\b").hasMatch(body), isTrue,
          reason: 'addInventoryItem debe persistir el precio derivado, no el crudo');
    });

    test('sync Shopify da de alta con unitCost (precio de tienda = costo), no con unitPrice', () {
      final src = File('lib/services/data_repository.dart').readAsStringSync();
      final body = _slice(src, 'Future<int> syncShopifyInventory(', 'return adjusted;');
      expect(body, isNotEmpty);
      // El alta por sync entra por addInventoryItem con unitCost: cat?.price (nunca unitPrice: cat…).
      expect(body.contains('unitCost: cat?.price'), isTrue,
          reason: 'el precio de la tienda Kura+ es el COSTO del centro');
      expect(RegExp(r'unitPrice:\s*cat').hasMatch(body), isFalse,
          reason: 'el sync NO debe meter el precio de la tienda como precio de venta');
    });

    test('inventario_screen: edición, CSV y formularios rutean por la regla (sin el legado × 1.3)',
        () {
      final src =
          File('lib/features/insumos/inventario_screen.dart').readAsStringSync();
      expect(src.contains('resolveSalePrice('), isTrue,
          reason: 'la edición y la re-subida del CSV deben rutear el precio por la regla');
      expect(src.contains('defaultSalePriceFromCost('), isTrue,
          reason: 'los formularios autocompletan el precio con la regla');
      // El default legado "costo +30 %" (× 1.3) se retiró: hoy es costo / 0.75.
      expect(RegExp(r'\*\s*1\.3\b').hasMatch(src), isFalse,
          reason: 'reapareció el default legado costo × 1.3; debe ser la regla única');
    });

    test('seed demo escribe unit_price por la regla, no por un factor a mano', () {
      final src = File('lib/services/local_db/demo_seed.dart').readAsStringSync();
      expect(src.contains("'unit_price': resolveSalePrice(cost:"), isTrue,
          reason: 'el inventario sembrado debe derivar el precio por la regla única');
    });
  });
}

/// Recorta el fragmento de fuente entre [start] (inclusive) y la primera [end] posterior (inclusive).
String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) return '';
  final j = src.indexOf(end, i);
  if (j < 0) return '';
  return src.substring(i, j + end.length);
}
