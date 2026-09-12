import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/services/data_repository.dart';

/// Precios SIEMPRE desde billing_catalog (0129 / demo_seed), nunca a mano en el Dart.
/// La prueba pública que hay que defender: 5 asientos + 5 Kura+ + los tres módulos
/// (mensual) = $7,000, el techo del autoservicio. Si la siembra no da exactamente
/// eso, algo quedó mal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('montos mensuales del catálogo (centavos, IVA incl.)', () async {
    final repo = await DataRepository.instance();
    int m(String kind, String key) => repo.unitAmountCents(kind, key, 'month');
    expect(repo.hasBillingCatalog, isTrue);
    expect(m('seat', 'clinico'), 40000); // $400
    expect(m('seat', 'protocolo'), 30000); // $300
    expect(m('module', 'admin'), 120000); // $1,200
    expect(m('module', 'insumos'), 140000); // $1,400
    expect(m('module', 'comercial'), 90000); // $900
  });

  test('techo del autoservicio = \$7,000/mes (5 asientos + 5 Kura+ + 3 módulos)',
      () async {
    final repo = await DataRepository.instance();
    int m(String kind, String key) => repo.unitAmountCents(kind, key, 'month');
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
          repo.unitAmountCents(e[0], e[1], 'month') * 10,
          reason: '${e[1]} anual = ×10 mensual');
    }
  });
}
