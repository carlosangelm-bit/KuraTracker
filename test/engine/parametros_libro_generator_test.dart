// Generador del "Libro de Parámetros Clínicos" (Fase A del refactor
// data-driven). A partir de assets/engine/clinical/*.json produce un documento
// legible en español (docs/generated/Libro_Parametros_Clinicos.md) con, por
// cada umbral/mapeo/banda: valor + procedencia (protocolo, justificación,
// revisor y fecha). El PR incluye el diff de este archivo para que María lo
// revise.
//
// El test SIEMPRE regenera el archivo (queda como artefacto versionado) y
// verifica que quede sincronizado con los JSON. Si cambia un parámetro, el diff
// del libro lo evidencia.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _outPath = 'docs/generated/Libro_Parametros_Clinicos.md';

void main() {
  test('genera docs/generated/Libro_Parametros_Clinicos.md desde los JSON', () {
    final thresholds = jsonDecode(
      File('assets/engine/clinical/thresholds.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final archetypes = jsonDecode(
      File('assets/engine/clinical/archetypes.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final md = _buildBook(thresholds: thresholds, archetypes: archetypes);

    Directory('docs/generated').createSync(recursive: true);
    File(_outPath).writeAsStringSync(md);

    // Sanidad: contiene las secciones y algún dato clave.
    expect(md, contains('# Libro de Parámetros Clínicos'));
    expect(md, contains('## Umbrales'));
    expect(md, contains('## Bandas de compresión'));
    expect(md, contains('## Mapeos por grado'));
    expect(md, contains('Protocolo LPP'));
  });
}

String _buildBook({
  required Map<String, dynamic> thresholds,
  required Map<String, dynamic> archetypes,
}) {
  final b = StringBuffer();
  b.writeln('# Libro de Parámetros Clínicos');
  b.writeln();
  b.writeln('> **Generado automáticamente** desde '
      '`assets/engine/clinical/thresholds.json` y `archetypes.json` por '
      '`test/engine/parametros_libro_generator_test.dart`. No editar a mano: '
      'cambiar un valor se hace en el JSON (con su procedencia) y este libro se '
      'regenera al correr los tests.');
  b.writeln();
  b.writeln('Versión de parámetros: `${thresholds['version']}`.');
  b.writeln();

  // --- Umbrales ---
  b.writeln('## Umbrales');
  b.writeln();
  b.writeln('| Parámetro | Valor | Unidad | Protocolo | Justificación | '
      'Revisado por | Fecha |');
  b.writeln('|---|---|---|---|---|---|---|');
  final ths = thresholds['thresholds'] as Map<String, dynamic>;
  for (final e in ths.entries) {
    final v = e.value as Map<String, dynamic>;
    final s = v['source'] as Map<String, dynamic>;
    b.writeln('| `${e.key}` | ${v['value']} | ${_cell(v['unit'])} | '
        '${_cell(s['protocolo'])} | ${_cell(s['rationale'])} | '
        '${_cell(s['reviewed_by'])} | ${_cell(s['reviewed_date'])} |');
  }
  b.writeln();

  // --- Bandas de compresión ---
  final cb = thresholds['compression_bands'] as Map<String, dynamic>;
  final cbSource = cb['source'] as Map<String, dynamic>;
  b.writeln('## Bandas de compresión');
  b.writeln();
  b.writeln('Dominio: **${cb['domain']}**. '
      '${_cell(cbSource['rationale'])} '
      '_(Protocolo: ${_cell(cbSource['protocolo'])}; revisado por '
      '${_cell(cbSource['reviewed_by'])}, ${_cell(cbSource['reviewed_date'])})_.');
  b.writeln();
  b.writeln('| Banda | Rango (ITB) |');
  b.writeln('|---|---|');
  for (final band in cb['bands'] as List) {
    final m = band as Map<String, dynamic>;
    b.writeln('| `${m['band']}` | ${_range(m)} |');
  }
  b.writeln();

  // --- Mapeos por grado ---
  b.writeln('## Mapeos por grado');
  b.writeln();
  final maps = archetypes['maps'] as Map<String, dynamic>;
  for (final entry in maps.entries) {
    final node = entry.value as Map<String, dynamic>;
    final s = node['source'] as Map<String, dynamic>;
    b.writeln('### `${entry.key}`');
    b.writeln();
    b.writeln('${_cell(node['description'])} '
        '_(Protocolo: ${_cell(s['protocolo'])}; ${_cell(s['rationale'])} '
        'Revisado por ${_cell(s['reviewed_by'])}, ${_cell(s['reviewed_date'])})_.');
    b.writeln();
    b.writeln('| Clave | Valor |');
    b.writeln('|---|---|');
    final map = node['map'] as Map<String, dynamic>;
    for (final me in map.entries) {
      b.writeln('| `${me.key}` | ${_cell(me.value)} |');
    }
    b.writeln();
  }

  return b.toString();
}

String _cell(dynamic v) => (v ?? '').toString().replaceAll('|', '\\|');

String _range(Map<String, dynamic> b) {
  final from = b['from'];
  final to = b['to'];
  final fi = b['from_inclusive'] as bool? ?? false;
  final ti = b['to_inclusive'] as bool? ?? false;
  final lo = from == null ? '−∞' : '$from';
  final hi = to == null ? '+∞' : '$to';
  final lb = from == null ? '(' : (fi ? '[' : '(');
  final rb = to == null ? ')' : (ti ? ']' : ')');
  return '$lb$lo, $hi$rb';
}
