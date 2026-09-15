// Datos derivados de Plataforma · Centros (§5.1), en la MISMA fuente que el panel de
// Licencia (center_license_data) para que no discrepen. Local: no arrastra google_fonts.
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/features/platform/derechos/center_license_data.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';
import 'package:kuratracker/services/remote/data_store.dart';

class _MemStore implements DataStore {
  final Map<String, List<Map<String, dynamic>>> data;
  _MemStore(this.data);
  @override
  List<Map<String, dynamic>> getAll(String c) => data[c] ?? const [];
  @override
  Future<Map<String, dynamic>> updateRow(String c, String id, Map<String, dynamic> p) async {
    final r = data[c]!.firstWhere((e) => e['id'] == id);
    r.addAll(p);
    return r;
  }
  @override
  Future<Map<String, dynamic>> insertRow(String c, Map<String, dynamic> d) async {
    (data[c] ??= []).add(d);
    return d;
  }
  @override
  Future<Map<String, dynamic>> upsertRow(String c, Map<String, dynamic> d) async =>
      insertRow(c, d);
  @override
  Future<void> deleteRow(String c, String id) async =>
      data[c]?.removeWhere((e) => e['id'] == id);
  @override
  Future<void> refreshCollection(String c) async {}
  @override
  Future<void> hydrate() async {}
}

Map<String, dynamic> _org(String id, {String type = 'clinica_heridas'}) =>
    {'id': id, 'name': 'Org $id', 'center_type': type, 'is_active': true};

Map<String, dynamic> _ent(String id, String org, String kind, String key,
        {String source = 'master',
        String status = 'active',
        int? quantity,
        String? end}) =>
    {
      'id': id,
      'organization_id': org,
      'kind': kind,
      'key': key,
      'quantity': quantity,
      'status': status,
      'source': source,
      'current_period_end': end,
      if (source == 'master') 'grant_type': 'cortesia',
      if (source == 'master') 'reason': 'semilla de prueba xx',
    };

Map<String, dynamic> _mod(String id, String org, String key, bool enabled) =>
    {'id': id, 'organization_id': org, 'module_key': key, 'enabled': enabled};

Future<DataRepository> _repo(Map<String, List<Map<String, dynamic>>> d) =>
    DataRepository.forSeeding(_MemStore(d));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la píldora se lee del DERECHO, no del interruptor', () async {
    // module:insumos con derecho ACTIVO, pero el interruptor de module_settings APAGADO.
    final repo = await _repo({
      Collections.organizations: [_org('o1')],
      Collections.orgEntitlements: [_ent('e1', 'o1', 'module', 'insumos')],
      Collections.moduleSettings: [_mod('m1', 'o1', 'insumos', false)],
    });
    final rows = moduleLicenseRows(repo, 'o1');
    final insumos = rows.firstWhere((r) => r.key == 'insumos');
    expect(insumos.hasRight, isTrue, reason: 'el derecho está activo → píldora rellena');
    expect(insumos.switchOn, isFalse, reason: 'el interruptor está apagado, y no manda');
  });

  test('Origen da los tres valores', () async {
    final stripe = await _repo({
      Collections.organizations: [_org('s')],
      Collections.orgEntitlements: [_ent('e', 's', 'module', 'insumos', source: 'stripe')],
    });
    final master = await _repo({
      Collections.organizations: [_org('m')],
      Collections.orgEntitlements: [_ent('e', 'm', 'module', 'insumos', source: 'master')],
    });
    final mixed = await _repo({
      Collections.organizations: [_org('x')],
      Collections.orgEntitlements: [
        _ent('e1', 'x', 'module', 'insumos', source: 'stripe'),
        _ent('e2', 'x', 'module', 'admin', source: 'master'),
      ],
    });
    expect(centerOrigin(stripe, 's'), CenterOrigin.stripe);
    expect(centerOrigin(master, 'm'), CenterOrigin.master);
    expect(centerOrigin(mixed, 'x'), CenterOrigin.mixed);
    expect(centerOriginLabel(centerOrigin(stripe, 's')), 'Stripe');
    expect(centerOriginLabel(centerOrigin(master, 'm')), 'A mano');
    expect(centerOriginLabel(centerOrigin(mixed, 'x')), 'Mixto');
  });

  test('Requiere atención distingue vencido → vence pronto → "—"', () async {
    final now = DateTime(2026, 9, 15, 12);
    String iso(int days) => now.add(Duration(days: days)).toIso8601String();
    final repo = await _repo({
      Collections.organizations: [_org('exp'), _org('soon'), _org('nada')],
      Collections.orgEntitlements: [
        // Derecho ACTIVO ya vencido → solo lectura. Antes el bucle lo saltaba y salía "—".
        _ent('e1', 'exp', 'module', 'insumos', end: iso(-3)),
        _ent('e2', 'soon', 'module', 'insumos', end: iso(26)),
      ],
      Collections.moduleSettings: [
        _mod('m1', 'nada', 'insumos', false),
        _mod('m2', 'nada', 'comercial', false),
      ],
    });
    final exp = centerAttention(repo, 'exp', now: now);
    final soon = centerAttention(repo, 'soon', now: now);
    final nada = centerAttention(repo, 'nada', now: now);

    expect(exp.isExpired, isTrue, reason: 'un derecho activo con fecha pasada = vencido');
    expect(centerAttentionLabel(exp), 'Venció hace 3 d');
    expect(soon.isExpired, isFalse);
    expect(centerAttentionLabel(soon), 'Vence en 26 d');
    expect(centerAttentionLabel(nada), '—');
  });
}
