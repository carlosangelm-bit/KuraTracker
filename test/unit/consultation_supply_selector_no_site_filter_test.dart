// GUARDA (Carlos, 19-sep): el flujo de insumos NUNCA se limita por sitio. El selector manual y el
// mapeo antiguo de la pantalla de consulta deben listar el inventario del CENTRO, no el del sitio
// de la consulta —si no, una paciente en un sitio sin inventario abre el selector vacío ("No hay
// inventario en el sitio de esta consulta"), la misma costura que el precio (cd5e3b3) y la
// resolución (0149)—. Derivada de la FUENTE: si alguien vuelve a pasar `siteId` a listInventoryItems
// en esta pantalla, esto se pone rojo. Es una guarda de "mira el resultado" de la fuente, no de la
// pantalla renderizada: enumera las llamadas reales, no una lista escrita a mano.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consultation_detail no filtra listInventoryItems por sitio (flujo de insumos sin límite)',
      () {
    final src = File('lib/features/consultation/consultation_detail_screen.dart')
        .readAsStringSync();
    // Todas las llamadas a listInventoryItems( … ) de la pantalla, con su lista de argumentos.
    final calls = RegExp(r'listInventoryItems\(([^)]*)\)').allMatches(src);
    expect(calls, isNotEmpty,
        reason: 'la pantalla lista inventario para el selector; si ya no, revisa esta guarda');
    final withSite = [
      for (final m in calls)
        if (m.group(1)!.contains('siteId')) m.group(0)!
    ];
    expect(withSite, isEmpty,
        reason: 'el selector/mapeo de insumos de la consulta NO debe filtrar por sitio '
            '(el inventario del centro cuenta esté en el sitio que esté): $withSite');
  });
}
