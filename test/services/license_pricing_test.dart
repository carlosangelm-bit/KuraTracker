import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/features/admin/license_plan_builder_screen.dart'
    show moneyOrDash, pesosFromCents;
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// Precios SIEMPRE desde billing_catalog (0129 / demo_seed), nunca a mano en el Dart.
/// La prueba pública que hay que defender: 5 asientos + 5 Kura+ + los tres módulos
/// (mensual) = $7,000, el techo del autoservicio. Y el invariante del punto 2: un
/// precio ausente es null, se pinta "—", NUNCA "$0".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('montos mensuales del catálogo (centavos, IVA incl.)', () async {
    final repo = await DataRepository.instance();
    int m(String kind, String key) => repo.unitAmountCents(kind, key, 'month')!;
    expect(m('seat', 'clinico'), 40000); // $400
    expect(m('seat', 'protocolo'), 30000); // $300
    expect(m('module', 'admin'), 120000); // $1,200
    expect(m('module', 'insumos'), 140000); // $1,400
    expect(m('module', 'comercial'), 90000); // $900
  });

  test('techo del autoservicio = \$7,000/mes (5 asientos + 5 Kura+ + 3 módulos)',
      () async {
    final repo = await DataRepository.instance();
    int m(String kind, String key) => repo.unitAmountCents(kind, key, 'month')!;
    final ceiling = 5 * m('seat', 'clinico') +
        5 * m('seat', 'protocolo') +
        m('module', 'admin') +
        m('module', 'insumos') +
        m('module', 'comercial');
    expect(ceiling, 700000, reason: '\$7,000 en centavos');
  });

  test('anual = ×10 del mensual (monto completo, el Dart nunca multiplica)',
      () async {
    final repo = await DataRepository.instance();
    for (final e in const [
      ['seat', 'clinico'],
      ['seat', 'protocolo'],
      ['module', 'admin'],
      ['module', 'insumos'],
      ['module', 'comercial'],
    ]) {
      expect(repo.unitAmountCents(e[0], e[1], 'year'),
          repo.unitAmountCents(e[0], e[1], 'month')! * 10,
          reason: '${e[1]} anual = ×10 mensual');
    }
  });

  test('precio ausente → null y "—", NUNCA "\$0" (fallo por fila, no todo-o-nada)',
      () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    // Fila del catálogo SIN unit_amount (concepto inventado para la prueba).
    await store.upsert(Collections.billingCatalog, {
      'id': 'qa_sin_monto_mensual',
      'lookup_key': 'qa_sin_monto_mensual',
      'kind': 'module',
      'key': 'qa_sin_monto',
      'interval': 'month',
      'unit': 'center',
      // sin unit_amount a propósito
    });
    // Fila totalmente ausente y fila presente-pero-sin-monto → ambas null.
    expect(repo.unitAmountCents('module', 'no_existe', 'month'), isNull);
    expect(repo.unitAmountCents('module', 'qa_sin_monto', 'month'), isNull);

    // La capa de despliegue: null → "—"; un cero REAL sí es "$0".
    expect(moneyOrDash(repo.unitAmountCents('module', 'qa_sin_monto', 'month')),
        '—');
    expect(moneyOrDash(null), '—');
    expect(moneyOrDash(0), pesosFromCents(0)); // "$0" solo para un cero de verdad
    expect(moneyOrDash(0), isNot('—'));
  });

  test('tabla + tarjetas de módulo = hero (\$4,700): 3 asientos + admin + insumos '
      '+ comercial; el cupo admin se cobra UNA vez', () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'price-4700';
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-seat-clinico',
      'organization_id': org,
      'kind': 'seat',
      'key': 'clinico',
      'quantity': 3,
      'status': 'active',
      'source': 'master',
    });
    for (final k in const ['admin', 'insumos', 'comercial']) {
      await store.upsert(Collections.orgEntitlements, {
        'id': '$org-module-$k',
        'organization_id': org,
        'kind': 'module',
        'key': k,
        'status': 'active',
        'source': 'master',
      });
    }

    final tbl = repo.licenseTableTotalFor(org);
    final mod = repo.licenseModuleTotalFor(org);
    final hero = repo.licenseHeroTotalFor(org);
    // El cupo administrativo NO se cobra en la tabla (va en su tarjeta): la tabla es
    // solo los 3 asientos clínicos.
    expect(tbl.cents, 120000, reason: '3 × \$400, sin el módulo admin');
    // admin + insumos + comercial, una vez cada uno.
    expect(mod.cents, 350000, reason: '\$1,200 + \$1,400 + \$900');
    expect(hero.cents, 470000, reason: '\$4,700');
    // La regla: lo visible (tabla + tarjetas) suma EXACTO el hero.
    expect(tbl.cents + mod.cents, hero.cents);
  });
}
