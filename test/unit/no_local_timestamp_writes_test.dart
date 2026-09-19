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
  // Deuda conocida (19-sep-2026): 46 escrituras en hora local en lib/ (baja 54→46 al pasar a UTC
  // las TABLAS DE DINERO —charges, charge_items, consultation_supply_usage— en sus 8 escrituras de
  // created_at/updated_at: en hora local un cobro tras las 18:00 del centro se contaba el día
  // anterior; los modelos castean created_at no-nulo y LocalStore no emula el default, así que se
  // manda UTC desde el cliente). 46→43 al pasar point_payments (bandeja de conciliación de MP
  // Point, TAMBIÉN dinero: linked_at/created_at/updated_at) a UTC. BAJA al migrar cada tabla a la
  // base/UTC. Ya arreglados y FUERA de la cuenta:
  //  · protocol_catalog_rules: el cliente NO escribe created_at/updated_at (el modelo NO los lee;
  //    la base los dueña vía 0136 default + 0146 trigger).
  //  · EVENTOS del grupo (b) a UTC EXPLÍCITO (`.toUtc()`): consents.granted_at,
  //    consultations.follow_up_signed_at, assessed_at (risk+scale), admitted_at/discharged_at,
  //    applied_at, started_at/placed_at (VAC), noted_at (×2), clinician_decision_at/returned_at,
  //    paid_at.
  //  · created_at de consents/consultations/wounds: en UTC EXPLÍCITO por el cliente (NO removido).
  //    OJO: LocalStore (demo) NO emula el `default now()` de prod y el modelo castea created_at
  //    no-nulo → si se quita la escritura, truena en demo. La quita queda para cuando LocalStore
  //    emule el default (deuda de auditoría (a)).
  // Lo que sigue en la cuenta es AUDITORÍA (created_at/updated_at que el cliente aún sella en hora
  // local): deuda aparte, se salda emulando el default en LocalStore + trigger set_updated_at por
  // tabla + quitar la escritura. Los 6 sitios ya correctos usan `.toUtc()` y NO cuentan.
  const knownLocalTimestampDebt = 43;

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
