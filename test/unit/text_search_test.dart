// Búsqueda sin acentos (hallazgo de Carlos: "apos" → "Sin resultados"). En español,
// ignorar acentos es de uso, no un detalle.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/core/utils/text_search.dart';

void main() {
  test('foldAccents baja mayúsculas y quita acentos', () {
    expect(foldAccents('Apósito'), 'aposito');
    expect(foldAccents('ÁÉÍÓÚñ'), 'aeioun');
  });

  test('matchesSearch: "apos" encuentra "Apósito de prueba"', () {
    expect(matchesSearch('Apósito de prueba (Almacén)', 'apos'), isTrue);
    expect(matchesSearch('Apósito de prueba (Almacén)', 'prueba'), isTrue);
    expect(matchesSearch('Apósito de prueba (Almacén)', 'almacen'), isTrue);
    expect(matchesSearch('Apósito de prueba', 'gasa'), isFalse);
  });

  test('matchesSearch: consulta vacía coincide (sin filtro)', () {
    expect(matchesSearch('lo que sea', ''), isTrue);
    expect(matchesSearch('lo que sea', '   '), isTrue);
  });
}
