// META-GUARD (Carlos) del sello en HORA LOCAL. `DateTime.now().toIso8601String()` toma
// la hora del DISPOSITIVO SIN zona; sobre una columna timestamptz Postgres la interpreta
// como UTC → desfase (UTC−6 en México = +6 h). El arreglo correcto es que la BASE ponga
// el sello (default/trigger), o —para lo que el usuario captura de verdad— UTC EXPLÍCITO
// (`.toUtc()`). Este patrón está copiado en muchos sitios (grupo (a) auditoría, (b) hechos
// clínicos/legales, (c) efímeros); se migra TABLA POR TABLA (disparador antes de quitar la
// escritura del cliente).
//
// Esta reja PINA la deuda actual y falla si aparece uno NUEVO. NUNCA debe SUBIR; al migrar
// una tabla a la base/UTC, BAJA este número. Cuando llegue a 0, la deuda está saldada.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Deuda conocida (17-sep-2026): 66 escrituras en hora local en lib/. Ya arreglados y
  // FUERA de la cuenta: protocol_catalog_rules (base, 0146) y consents (created_at → default
  // 0026; granted_at → toUtc explícito). Los 6 sitios correctos usan `.toUtc()` y NO cuentan.
  const knownLocalTimestampDebt = 66;

  test('no aparecen sellos en HORA LOCAL nuevos (DateTime.now().toIso8601String())', () {
    // Coincide LOCAL: DateTime.now().toIso8601String() SIN `.toUtc()` en medio.
    final local = RegExp(r'DateTime\.now\(\)\.toIso8601String\(\)');
    var count = 0;
    final byFile = <String, int>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final n = local.allMatches(f.readAsStringSync()).length;
      if (n > 0) {
        count += n;
        byFile[f.uri.pathSegments.last] = n;
      }
    }
    expect(count, lessThanOrEqualTo(knownLocalTimestampDebt),
        reason: 'Apareció un sello en HORA LOCAL nuevo (total $count > deuda '
            '$knownLocalTimestampDebt). Usa la BASE (default/trigger) o `.toUtc()` '
            'explícito, nunca DateTime.now().toIso8601String() sobre timestamptz.\n'
            'Por archivo: $byFile');
    expect(count, knownLocalTimestampDebt,
        reason: 'La deuda de sellos locales cambió a $count. Si BAJASTE (migraste una '
            'tabla a la base/UTC), actualiza knownLocalTimestampDebt a $count. NUNCA la subas.');
  });
}
