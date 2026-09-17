// #4 (Carlos) — los ESCRITORES de protocol_catalog_rules, ENUMERADOS. La falla de la
// casa es un candado nuevo sin enumerar a todos los que escriben. Hoy son CUATRO:
//   (1) CLIENTE: DataRepository.saveProtocolCatalogRule (upsertRow) +
//       deleteProtocolCatalogRule (deleteRow) — gateados por la RLS.
//   (2) RLS: policy `protocol_catalog_rules_all` (0142) `for all using/with check
//       current_user_can_author_catalog()` — la PUERTA.
//   (3) TRIGGER: en la tabla (0136 `after insert or update or delete`) — deriva/valida
//       en cada escritura.
//   (4) SEMILLA: `insert into protocol_catalog_rules` (0141) — las 35 reglas, service role.
// Estas rejas de FUENTE fallan si aparece un QUINTO escritor no enumerado.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CLIENTE: exactamente 2 escrituras (save=upsert, delete), en data_repository', () {
    final src =
        File('lib/services/data_repository.dart').readAsStringSync();
    final writes = RegExp(
      r'(upsertRow|insertRow|updateRow|deleteRow)\(\s*Collections\.protocolCatalogRules',
    ).allMatches(src).length;
    expect(writes, 2,
        reason: 'El cliente escribe protocol_catalog_rules en EXACTAMENTE 2 puntos '
            '(saveProtocolCatalogRule upsert + deleteProtocolCatalogRule delete). '
            'Si cambió, hay un escritor nuevo: enumera y actualiza esta reja.');
  });

  test('SQL: la ÚNICA DML (insert/update/delete) a protocol_catalog_rules es la semilla 0141',
      () {
    final dml = RegExp(
      r'(insert\s+into|update|delete\s+from)\s+(public\.)?protocol_catalog_rules',
      caseSensitive: false,
    );
    final offenders = <String>[];
    for (final f in Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))) {
      if (dml.hasMatch(f.readAsStringSync()) && !f.path.contains('0141')) {
        offenders.add(f.uri.pathSegments.last);
      }
    }
    expect(offenders, isEmpty,
        reason: 'DML nueva a protocol_catalog_rules fuera de la semilla 0141 '
            '(un escritor SQL nuevo): ${offenders.join(', ')}. Enumera y actualiza la reja.');
  });

  test('SQL: la PUERTA (policy) y el TRIGGER están donde se enumeran (0142 / 0136)', () {
    // El escritor (2)=RLS vive en 0142; (3)=trigger en 0136. Si otra migración
    // redefine la policy o agrega un trigger a la tabla, hay que RE-ENUMERAR.
    final policyMigs = <String>[];
    final triggerMigs = <String>[];
    for (final f in Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))) {
      final src = f.readAsStringSync();
      final name = f.uri.pathSegments.last;
      if (RegExp(r'create\s+policy[^;]*on\s+public\.protocol_catalog_rules',
              caseSensitive: false)
          .hasMatch(src)) {
        policyMigs.add(name);
      }
      if (RegExp(r'create\s+trigger[^;]*on\s+public\.protocol_catalog_rules',
              caseSensitive: false)
          .hasMatch(src)) {
        triggerMigs.add(name);
      }
    }
    // La policy se REDEFINE por historia (0136→0137→0142); la VIGENTE es 0142.
    expect(policyMigs.any((m) => m.startsWith('0142')), isTrue,
        reason: 'la policy vigente de protocol_catalog_rules debe estar en 0142');
    // DOS triggers ENUMERADOS sobre la tabla: (3a) auditoría (0136) y (3b) set_updated_at
    // (0146 — la BASE dueña de updated_at; el cliente dejó de escribirlo). Si aparece OTRO
    // archivo con trigger, es un escritor/candado nuevo: enumera y actualiza la reja.
    expect(
        triggerMigs.toSet(),
        {
          '0136_protocol_catalog_matrix_schema.sql',
          '0146_protocol_catalog_rules_updated_at.sql',
        },
        reason: 'trigger(s) sobre protocol_catalog_rules fuera de los enumerados: '
            '$triggerMigs. Un trigger nuevo es un escritor/candado nuevo.');
  });
}
