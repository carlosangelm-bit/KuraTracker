import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// §3 del catálogo de insumos: product_catalog gana kura_tag + generic_product
/// (clasificación clínica), y el requisito CRÍTICO es que shopify-sync-catalog
/// NO las pise en el re-sync. La preservación es conductual (upsert de Postgres),
/// pero se puede DETECTAR EL REVERT: si alguien mete esas columnas en el payload
/// del upsert, un catálogo nuevo borraría la clasificación → este test se pone
/// rojo. Y confirma que la migración agrega las columnas.
void main() {
  test('0124 agrega kura_tag y generic_product a product_catalog', () {
    final m = File(
            'supabase/migrations/0124_product_catalog_classification.sql')
        .readAsStringSync();
    final flat = m.replaceAll(RegExp(r'\s+'), ' ');
    expect(flat, contains('alter table public.product_catalog'));
    expect(flat, contains('add column if not exists kura_tag text'));
    expect(flat, contains('add column if not exists generic_product text'));
  });

  test('shopify-sync-catalog NO pisa la clasificación (no está en el upsert)',
      () {
    final fn =
        File('supabase/functions/shopify-sync-catalog/index.ts').readAsStringSync();
    // El objeto que se sube (rows.push) no debe asignar estas columnas.
    expect(fn.contains('kura_tag:'), isFalse,
        reason: 'kura_tag en el payload del sync BORRARÍA la clasificación');
    expect(fn.contains('generic_product:'), isFalse,
        reason: 'generic_product en el payload del sync BORRARÍA la clasificación');
  });
}
