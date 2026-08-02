import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Construye un CSV plano con TODOS los parámetros clínicos del motor de reglas
/// (umbrales, bandas de compresión y mapeos por grado) leídos de
/// `assets/engine/clinical/*.json`, cada fila con su procedencia (protocolo,
/// justificación, revisor, fecha). Es la fuente única de la descarga del master
/// y comparte los MISMOS assets que consume el motor, así que nunca se
/// desincroniza de la conducta clínica vigente.
class ClinicalParamsCsv {
  /// Encabezados del CSV (esquema unificado para las tres secciones).
  static const List<String> headers = [
    'seccion',
    'clave',
    'subclave',
    'valor',
    'unidad',
    'protocolo',
    'justificacion',
    'revisado_por',
    'fecha_revision',
  ];

  /// Lee los assets y arma `(filename, content)` listo para `downloadCsv()`.
  static Future<({String filename, String content})> build() async {
    final thresholds = jsonDecode(
      await rootBundle.loadString('assets/engine/clinical/thresholds.json'),
    ) as Map<String, dynamic>;
    final archetypes = jsonDecode(
      await rootBundle.loadString('assets/engine/clinical/archetypes.json'),
    ) as Map<String, dynamic>;

    final rows = <List<dynamic>>[headers];

    // --- Umbrales ---
    final ths = (thresholds['thresholds'] as Map).cast<String, dynamic>();
    ths.forEach((key, entry) {
      final e = (entry as Map).cast<String, dynamic>();
      final s = _source(e['source']);
      rows.add([
        'umbral',
        key,
        '',
        e['value'],
        e['unit'] ?? '',
        ...s,
      ]);
    });

    // --- Bandas de compresión ---
    final cb = (thresholds['compression_bands'] as Map).cast<String, dynamic>();
    final cbSource = _source(cb['source']);
    for (final band in (cb['bands'] as List)) {
      final m = (band as Map).cast<String, dynamic>();
      rows.add([
        'banda_compresion',
        m['band'],
        'rango',
        _range(m),
        cb['domain'] ?? 'ITB',
        ...cbSource,
      ]);
    }

    // --- Mapeos por grado (arquetipos) ---
    final maps = (archetypes['maps'] as Map).cast<String, dynamic>();
    maps.forEach((mapKey, node) {
      final n = (node as Map).cast<String, dynamic>();
      final s = _source(n['source']);
      final map = (n['map'] as Map).cast<String, dynamic>();
      map.forEach((k, v) {
        rows.add([mapKey, k, '', v, '', ...s]);
      });
    });

    final content = const ListToCsvConverter(eol: '\r\n').convert(rows);
    final version = (thresholds['version'] ?? 'v1').toString();
    return (filename: 'parametros_clinicos_$version.csv', content: content);
  }

  /// Devuelve [protocolo, justificacion, revisado_por, fecha_revision].
  static List<String> _source(dynamic raw) {
    final s = raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
    return [
      (s['protocolo'] ?? '').toString(),
      (s['rationale'] ?? '').toString(),
      (s['reviewed_by'] ?? '').toString(),
      (s['reviewed_date'] ?? '').toString(),
    ];
  }

  /// Rango legible de una banda de compresión (ej. `[0.9, 1.4]`, `(-inf, 0.6)`).
  static String _range(Map<String, dynamic> b) {
    final from = b['from'];
    final to = b['to'];
    final fi = b['from_inclusive'] as bool? ?? false;
    final ti = b['to_inclusive'] as bool? ?? false;
    final lo = from == null ? '-inf' : '$from';
    final hi = to == null ? '+inf' : '$to';
    final lb = from == null ? '(' : (fi ? '[' : '(');
    final rb = to == null ? ')' : (ti ? ']' : ')');
    return '$lb$lo, $hi$rb';
  }
}
