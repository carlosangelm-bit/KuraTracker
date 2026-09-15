// Reja (patrón de la reja de paleta): enumera TODOS los escritores de filas
// source='master' en org_entitlements y falla si aparece uno NUEVO sin enumerar.
//
// Cada escritor debe producir filas que pasen ent_master_grant_shape (0132). La
// EJECUCIÓN contra Postgres de cada uno vive en supabase/tests/local/:
//   · 0114 backfill + 0135 create_trial_organization → run_master_row_writers.sh
//   · 0132 master_grant_entitlement (RPC)            → run.sh (master_grants_local_tests)
//   · 0133 toma de posesión de Stripe                → run.sh (stripe_takeover_local_tests)
//
// Este bug ya salió DOS veces (el seed del sandbox y create_trial_organization); la
// lista es lo que impide la tercera: un insert de fila master en una migración nueva no
// enumerada rompe esta prueba, obligando a enumerarla Y a darle ejecución contra el CHECK.
//
// Local: escaneo de archivos (dart:io), no monta nada.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// migración → por qué inserta (o insertó) una fila source='master'.
const _knownMasterRowWriters = <String, String>{
  '0114_license_backfill.sql':
      'backfill de licencias (one-shot); 0132 §2.2 rellena sus filas antes del CHECK',
  '0116_seat_counters_and_alta_guard.sql':
      'create_organization_with_admin (plan gratuito) — RETIRADA por 0126; insert muerto',
  '0125_create_trial_organization.sql':
      'create_trial_organization original — SUPERSEDED por 0135',
  '0132_master_grants.sql':
      'master_grant_entitlement (RPC); sus guardias exigen grant_type/reason',
  '0133_stripe_takeover_clears_master_fields.sql':
      'toma de posesión de Stripe; reescribe la fila a source=stripe (rama stripe del CHECK)',
  '0135_trial_org_grant_shape.sql':
      'create_trial_organization vigente; filas master con grant_type/reason/is_permanent',
};

void main() {
  test('todo escritor de filas source=master está enumerado (y con ejecución)', () {
    final dir = Directory('supabase/migrations');
    expect(dir.existsSync(), isTrue, reason: '¿ruta mal? no existe ${dir.path}');
    final insertRe = RegExp(r'insert\s+into\s+(?:public\.)?org_entitlements\b',
        caseSensitive: false);
    final masterRe = RegExp("'master'");

    final found = <String>{};
    for (final e in dir.listSync()) {
      if (e is! File || !e.path.endsWith('.sql')) continue;
      final src = e.readAsStringSync();
      for (final m in insertRe.allMatches(src)) {
        final rest = src.substring(m.start);
        final semi = rest.indexOf(';');
        final stmt = semi >= 0 ? rest.substring(0, semi) : rest;
        if (masterRe.hasMatch(stmt)) {
          found.add(e.uri.pathSegments.last);
          break;
        }
      }
    }

    final allow = _knownMasterRowWriters.keys.toSet();
    final nuevos = found.difference(allow);
    final idos = allow.difference(found);
    expect(nuevos, isEmpty,
        reason: 'Escritor(es) de filas source=master SIN enumerar: $nuevos. '
            'Añádelo a _knownMasterRowWriters Y a un arnés que EJECUTE su fila '
            'contra ent_master_grant_shape (supabase/tests/local/), o el bug sale '
            'una tercera vez.');
    expect(idos, isEmpty,
        reason: 'Enumerados que ya no insertan filas master (quítalos): $idos');
    expect(found.length, greaterThanOrEqualTo(4),
        reason: 'esperaba ≥4 escritores; ¿el escaneo dejó de encontrar inserts?');
  });
}
