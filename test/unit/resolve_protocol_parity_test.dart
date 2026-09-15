// Paridad Dart ↔ SQL del resolvedor, en el camino que AMBOS cubren: la tabla propia del
// centro (protocol_product_rules). Compila el CÓDIGO REAL de Dart (resolveProtocolProducts)
// y lo corre contra un corpus curado; corre resolve_protocol (SQL) sobre EL MISMO corpus en
// un Postgres desechable en Docker; y afirma que devuelven exactamente lo mismo — producto,
// cantidad, y ORDEN. El corpus barre pasos × exudado × zona × infección × cortes de área/
// volumen, con los BORDES de cada rango y los EMPATES de especificidad.
//
// Corre bajo `flutter test` (importa el código real de Dart, que arrastra Flutter y solo
// compila así). Necesita Docker para el Postgres desechable: si no lo hay (algún CI sin
// daemon), la prueba se SALTA con aviso en vez de fallar. Local: fvm flutter test <este>.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/remote/data_store.dart';
import 'package:kuratracker/models/note_option_catalog.dart';

// ---- Store en memoria (getAll basta para el resolvedor) ----------------------------------
class _MemStore implements DataStore {
  final Map<String, List<Map<String, dynamic>>> data;
  _MemStore(this.data);
  @override
  List<Map<String, dynamic>> getAll(String c) => data[c] ?? const [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('MemStore: ${i.memberName}');
}

const _org = '00000000-0000-0000-0000-0000000000aa';
const _site = '00000000-0000-0000-0000-0000000000bb';

// Ocho insumos en el inventario del centro + uno (Z) que NO está (huérfana).
const _items = <String, String>{
  'A': '10000000-0000-0000-0000-00000000000a',
  'B': '10000000-0000-0000-0000-00000000000b',
  'C': '10000000-0000-0000-0000-00000000000c',
  'D': '10000000-0000-0000-0000-00000000000d',
  'E': '10000000-0000-0000-0000-00000000000e',
  'F': '10000000-0000-0000-0000-00000000000f',
  'G': '10000000-0000-0000-0000-000000000010',
  'H': '10000000-0000-0000-0000-000000000011',
};
const _site2 = '00000000-0000-0000-0000-0000000000cc';
// Item REAL (FK válida) pero en OTRO sitio: el resolvedor (site=_site) lo excluye por sitio,
// igual que Dart. Es la huérfana "el insumo no está en este sitio".
const _itemZ = '1000000f-0000-0000-0000-000000000099';

int _seq = 0;
Map<String, dynamic> _rule(
  String category,
  String? item, {
  String dimension = 'none',
  double? minV,
  double? maxV,
  String qmode = 'fixed',
  double qval = 1,
  List<String> exudate = const [],
  List<String> zones = const [],
  String infection = 'any',
  int? sort,
}) =>
    {
      'id': '20000000-0000-0000-0000-${(_seq).toString().padLeft(12, '0')}',
      'organization_id': _org,
      'category': category,
      'inventory_item_id': item,
      'name': item,
      'dimension': dimension,
      'min_value': minV,
      'max_value': maxV,
      'quantity_mode': qmode,
      'quantity_value': qval,
      'sort_order': sort ?? (_seq),
      'exudate_levels': exudate,
      'zone_groups': zones,
      'infection': infection,
      'priority': 0,
    }..[r'$seq'] = _seq++;

// ---- Corpus de reglas -------------------------------------------------------------------
List<Map<String, dynamic>> _rules() {
  _seq = 0;
  return [
    // aposito: comodín (spec0) + dos por área con BORDES [0,10) y [10, +inf) (spec1).
    _rule('aposito', _items['A'], sort: 0),
    _rule('aposito', _items['B'], dimension: 'area', minV: 0, maxV: 10, sort: 1),
    _rule('aposito', _items['C'], dimension: 'area', minV: 10, maxV: null, sort: 2),
    // aposito: una por exudado (spec1) — para empatar especificidad con las de área.
    _rule('aposito', _items['H'], exudate: ['abundante'], sort: 3),
    // aposito: MÁS específica (área + exudado = spec2) → debe ganar sobre las spec1.
    _rule('aposito', _items['A'],
        dimension: 'area', minV: 0, maxV: 10, exudate: ['abundante'], sort: 4),
    // limpieza: dos comodines (spec0) → EMPATE, ambos salen (solución + gasa).
    _rule('limpieza', _items['F'], sort: 5),
    _rule('limpieza', _items['G'], sort: 6),
    // relleno_cavidad: por volumen con bordes [0,5) y [5,+inf), cantidad per_volume.
    _rule('relleno_cavidad', _items['D'],
        dimension: 'volume', minV: 0, maxV: 5, qmode: 'per_volume', qval: 0.5, sort: 7),
    _rule('relleno_cavidad', _items['E'],
        dimension: 'volume', minV: 5, maxV: null, qmode: 'per_volume', qval: 0.5, sort: 8),
    // dedup: mismo item D, dos reglas maxSpec — gana el de menor sort_order.
    _rule('relleno_cavidad', _items['D'],
        dimension: 'volume', minV: 0, maxV: 5, qval: 9, sort: 9),
    // zona + infección (spec2) en aposito, item G.
    _rule('aposito', _items['G'],
        zones: ['sacro_gluteo'], infection: 'yes', sort: 10),
    // HUÉRFANA: apunta a un item que NO está en inventario → se salta EN SILENCIO.
    _rule('aposito', _itemZ, dimension: 'area', minV: 0, maxV: 10, sort: 11),
  ];
}

// ---- Casos: barren las dimensiones y los bordes -----------------------------------------
class _Case {
  final String id;
  final Set<String> cats;
  final double? area, vol;
  final String? exudate, zone;
  final bool? infection;
  _Case(this.id, this.cats,
      {this.area, this.vol, this.exudate, this.zone, this.infection});
}

List<_Case> _cases() => [
      _Case('area-borde-inf', {'aposito'}, area: 0),        // 0 ∈ [0,10)
      _Case('area-dentro', {'aposito'}, area: 5),
      _Case('area-borde-sup', {'aposito'}, area: 10),       // 10 ∉ [0,10), ∈ [10,)
      _Case('area-just-antes', {'aposito'}, area: 9.99),
      _Case('area-grande', {'aposito'}, area: 50),
      _Case('area-null', {'aposito'}),                       // sin área: dim-rules no aplican
      _Case('area+exudado-spec2', {'aposito'}, area: 5, exudate: 'abundante'),
      _Case('exudado-solo', {'aposito'}, exudate: 'abundante'),
      _Case('exudado-otro', {'aposito'}, exudate: 'escaso'),
      _Case('zona+infeccion-spec2', {'aposito'}, zone: 'sacro_gluteo', infection: true),
      _Case('zona-sin-infeccion', {'aposito'}, zone: 'sacro_gluteo', infection: false),
      _Case('limpieza-empate', {'limpieza'}),
      _Case('relleno-borde-inf', {'relleno_cavidad'}, vol: 0),
      _Case('relleno-borde-sup', {'relleno_cavidad'}, vol: 5),
      _Case('relleno-dentro', {'relleno_cavidad'}, vol: 3),
      _Case('multi-cat', {'aposito', 'limpieza', 'relleno_cavidad'},
          area: 5, vol: 2, exudate: 'abundante'),
      _Case('cat-inexistente', {'desbridamiento'}, area: 5),
    ];

KuraTag? _tag(String db) {
  for (final t in KuraTag.values) {
    if (t.dbValue == db) return t;
  }
  return null;
}

String _round(num n) => (n).toStringAsFixed(3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('paridad Dart ↔ SQL del resolvedor sobre protocol_product_rules', () async {
  // Arnés de Docker, como los demás de supabase/tests/local/: se corre EN LOCAL
  // (fvm flutter test <este>), no en el `checks` de CI, para no meter Postgres en la ruta
  // crítica del deploy. Se salta si estamos en CI o si no hay daemon de Docker.
  if (Platform.environment['CI'] == 'true') {
    markTestSkipped('CI: la paridad se verifica en local (arnés Docker). No bloquea el deploy.');
    return;
  }
  final dockerOk = (await Process.run('docker', ['info'])).exitCode == 0;
  if (!dockerOk) {
    markTestSkipped('Docker no disponible: se salta la paridad (no falla).');
    return;
  }
  final rules = _rules();
  final inv = [
    for (final e in _items.entries)
      {'id': e.value, 'organization_id': _org, 'site_id': _site, 'name': e.key,
       'unit_cost': 1.0, 'currency': 'MXN', 'is_active': true},
    // La huérfana: existe (FK válida) pero en OTRO sitio → fuera del inventario de _site.
    {'id': _itemZ, 'organization_id': _org, 'site_id': _site2, 'name': 'Z-otro-sitio',
     'unit_cost': 1.0, 'currency': 'MXN', 'is_active': true},
  ];
  final repo = await DataRepository.forSeeding(_MemStore({
    'protocol_product_rules': rules,
    'inventory_items': inv,
    'org_entitlements': const [], // sin Kura+ → camino propio
  }));

  // --- Salida de Dart por caso ---
  final dartOut = <String, List<Map<String, dynamic>>>{};
  for (final c in _cases()) {
    final r = repo.resolveProtocolProducts(
      organizationId: _org,
      categories: {for (final s in c.cats) _tag(s)}.whereType<KuraTag>().toSet(),
      areaCm2: c.area,
      volumeCm3: c.vol,
      exudateLevel: c.exudate,
      zoneGroup: c.zone,
      infectionSuspected: c.infection,
      siteId: _site,
    );
    dartOut[c.id] = [
      for (final p in r)
        {'category': p.category, 'item': p.inventoryItemId, 'name': p.name, 'qty': _round(p.quantity)}
    ];
  }

  // --- Genera el SQL: cadena de migraciones + inserts del corpus + un query por caso ---
  final sb = StringBuffer();
  sb.writeln("insert into public.organizations (id, name) values ('$_org','corpus') on conflict do nothing;");
  for (final it in inv) {
    sb.writeln("insert into public.inventory_items (id, organization_id, site_id, name, unit_cost, currency, is_active) values "
        "('${it['id']}','$_org','${it['site_id']}','${it['name']}',1.0,'MXN',true);");
  }
  // El centro del corpus NO tiene protocol:author ni seat:protocolo → camino propio.
  for (final rl in rules) {
    sb.writeln("insert into public.protocol_product_rules "
        "(id, organization_id, category, inventory_item_id, name, dimension, min_value, max_value, quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection, priority) values ("
        "'${rl['id']}','$_org','${rl['category']}',${rl['inventory_item_id'] == null ? 'null' : "'${rl['inventory_item_id']}'"},"
        "${rl['name'] == null ? 'null' : "'${rl['name']}'"},'${rl['dimension']}',"
        "${rl['min_value'] ?? 'null'},${rl['max_value'] ?? 'null'},'${rl['quantity_mode']}',${rl['quantity_value']},${rl['sort_order']},"
        "'${jsonEncode(rl['exudate_levels'])}'::jsonb,'${jsonEncode(rl['zone_groups'])}'::jsonb,'${rl['infection']}',${rl['priority']});");
  }
  for (final c in _cases()) {
    final cats = "array[${c.cats.map((s) => "'$s'").join(',')}]::text[]";
    String n(double? d) => d == null ? 'null' : d.toString();
    final infection = c.infection == null ? 'null' : c.infection.toString();
    sb.writeln("select '${c.id}' as case_id, coalesce(jsonb_agg(jsonb_build_object("
        "'category',r.category,'item',r.inventory_item_id,'name',r.name,'qty',to_char(round(r.quantity,3),'FM990.000')) order by r.ord),'[]'::jsonb) as result "
        "from public.resolve_protocol('$_org',$cats,${n(c.area)},${n(c.vol)},"
        "${c.exudate == null ? 'null' : "'${c.exudate}'"},${c.zone == null ? 'null' : "'${c.zone}'"},"
        "$infection,'$_site',null,null) with ordinality as r(category, inventory_item_id, name, quantity, brand, alt_name, alt_brand, note_phrase, source, ord);");
  }

  // --- Docker: levanta Postgres, carga cadena + corpus, corre los queries ---
  const cont = 'kt-pg-resolveparity';
  await Process.run('docker', ['rm', '-f', cont]);
  final up = await Process.run('docker', [
    'run', '-d', '--name', cont, '-e', 'POSTGRES_PASSWORD=pw', '-e', 'POSTGRES_DB=kt',
    '-p', '55455:5432', 'postgres:15'
  ]);
  if (up.exitCode != 0) {
    stderr.writeln('No se pudo levantar Postgres: ${up.stderr}');
    exit(2);
  }
  try {
    for (var i = 0; i < 30; i++) {
      final r = await Process.run('docker', ['exec', cont, 'pg_isready', '-U', 'postgres']);
      if (r.exitCode == 0) break;
      await Future.delayed(const Duration(seconds: 1));
    }
    Future<ProcessResult> psql(String sql) => Process.start('docker',
            ['exec', '-i', cont, 'psql', '-U', 'postgres', '-d', 'kt', '-v', 'ON_ERROR_STOP=1', '-tA'])
        .then((p) {
      p.stdin.write(sql);
      p.stdin.close();
      return Future.wait([p.stdout.transform(utf8.decoder).join(),
              p.stderr.transform(utf8.decoder).join(), p.exitCode])
          .then((v) => ProcessResult(p.pid, v[2] as int, v[0], v[1]));
    });
    // cadena de migraciones
    final chain = [
      'supabase/tests/local/protocol_catalog_fixture.sql',
      'supabase/migrations/0076_protocol_product_rules.sql',
      'supabase/migrations/0077_protocol_rule_conditions.sql',
      'supabase/migrations/0136_protocol_catalog_matrix_schema.sql',
      'supabase/migrations/0137_protocol_catalog_admin_only.sql',
      'supabase/migrations/0138_org_entitlement_vigente.sql',
      'supabase/migrations/0139_resolve_protocol.sql',
    ];
    for (final f in chain) {
      final r = await psql(await File(f).readAsString());
      if (r.exitCode != 0) fail('Falló $f:\n${r.stderr}');
    }
    final out = await psql(sb.toString());
    if (out.exitCode != 0) fail('Falló el corpus SQL:\n${out.stderr}');

    // psql -tA da lineas "case_id|json"
    final sqlOut = <String, List<Map<String, dynamic>>>{};
    for (final line in const LineSplitter().convert(out.stdout as String)) {
      final i = line.indexOf('|');
      if (i < 0) continue;
      final id = line.substring(0, i);
      final arr = (jsonDecode(line.substring(i + 1)) as List).cast<Map<String, dynamic>>();
      sqlOut[id] = arr;
    }

    // --- Comparación: por CAMPO y en ORDEN (no por texto JSON, cuyo orden de claves difiere
    // entre Dart y jsonb). Compara producto, cantidad, nombre y categoría, respetando el orden
    // de la lista (el orden del régimen también es parte de la paridad). ---
    String key(Map m) => '${m['category']}|${m['item']}|${m['name']}|${m['qty']}';
    bool sameList(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (key(a[i]) != key(b[i])) return false;
      }
      return true;
    }

    var fails = 0;
    for (final c in _cases()) {
      final d = dartOut[c.id]!;
      final s = sqlOut[c.id] ?? const [];
      if (!sameList(d, s)) {
        fails++;
        stdout.writeln('DIFF [${c.id}]');
        stdout.writeln('  Dart: ${d.map(key).toList()}');
        stdout.writeln('  SQL : ${s.map(key).toList()}');
      }
    }
    expect(fails, 0,
        reason: 'PARIDAD FALLA: $fails caso(s) difieren (ver arriba). Un caso donde '
            'difieran es un HALLAZGO, no un ajuste: reportar antes de tocar ninguno.');
    // ignore: avoid_print
    print('PARIDAD OK: ${_cases().length} casos, Dart == SQL (producto, cantidad, orden).');
  } finally {
    await Process.run('docker', ['rm', '-f', cont]);
  }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
