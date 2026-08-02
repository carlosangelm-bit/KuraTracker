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
    return buildFromMaps(thresholds: thresholds, archetypes: archetypes);
  }

  /// Igual que [build] pero desde los mapas ya decodificados (usado por tests y
  /// por la vista previa de una carga).
  static ({String filename, String content}) buildFromMaps({
    required Map<String, dynamic> thresholds,
    required Map<String, dynamic> archetypes,
  }) {
    final version = (thresholds['version'] ?? 'v1').toString();
    final rows = <List<dynamic>>[headers];
    // Fila meta con la versión, para que la carga pueda reconstruir el JSON
    // sin pérdida (round-trip). Se ignora en la vista de datos.
    rows.add(['meta', 'version', '', version, '', '', '', '', '']);

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
    return (filename: 'parametros_clinicos_$version.csv', content: content);
  }

  /// Reconstruye los mapas `thresholds` y `archetypes` (listos para
  /// `ClinicalParams.fromJsonStrings`/validación y para persistir) a partir de
  /// un CSV con el mismo esquema que produce [build]. Tolera BOM y filas en
  /// desorden; toma la versión de la fila `meta`/`version` (o un fallback).
  static ({
    Map<String, dynamic> thresholds,
    Map<String, dynamic> archetypes,
    String version,
  }) parse(String csv) {
    var text = csv;
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1); // quitar BOM UTF-8
    }
    final rows =
        const CsvToListConverter(eol: '\r\n', shouldParseNumbers: false)
            .convert(text);
    if (rows.length < 2) {
      throw const FormatException('CSV vacío o sin filas de datos.');
    }
    final header = rows.first.map((e) => e.toString().trim()).toList();
    int col(String name) {
      final i = header.indexOf(name);
      if (i < 0) throw FormatException('Falta la columna "$name" en el CSV.');
      return i;
    }

    final cSec = col('seccion'),
        cKey = col('clave'),
        cVal = col('valor'),
        cUnit = col('unidad'),
        cProt = col('protocolo'),
        cRat = col('justificacion'),
        cRev = col('revisado_por'),
        cDate = col('fecha_revision');

    String cell(List<dynamic> r, int i) =>
        i < r.length ? (r[i] ?? '').toString() : '';
    Map<String, dynamic> src(List<dynamic> r) => {
          'protocolo': cell(r, cProt),
          'rationale': cell(r, cRat),
          'reviewed_by': cell(r, cRev),
          'reviewed_date': cell(r, cDate),
        };

    var version = 'clinical_params_v1';
    final thresholds = <String, dynamic>{};
    final bands = <Map<String, dynamic>>[];
    Map<String, dynamic>? bandSource;
    var bandDomain = 'ITB';
    final maps = <String, Map<String, dynamic>>{};

    for (final r in rows.skip(1)) {
      final seccion = cell(r, cSec).trim();
      final clave = cell(r, cKey).trim();
      if (seccion.isEmpty && clave.isEmpty) continue;
      switch (seccion) {
        case 'meta':
          if (clave == 'version' && cell(r, cVal).trim().isNotEmpty) {
            version = cell(r, cVal).trim();
          }
          break;
        case 'umbral':
          thresholds[clave] = {
            'value': _num(cell(r, cVal)),
            'unit': cell(r, cUnit),
            'source': src(r),
          };
          break;
        case 'banda_compresion':
          bandSource ??= src(r);
          if (cell(r, cUnit).trim().isNotEmpty) bandDomain = cell(r, cUnit).trim();
          bands.add({'band': clave, ..._parseRange(cell(r, cVal))});
          break;
        default:
          // Mapeos por grado (wagner_descarga, wuwhs_manejo, compresion_producto…)
          final m = maps.putIfAbsent(
              seccion, () => {'source': src(r), 'map': <String, dynamic>{}});
          (m['map'] as Map<String, dynamic>)[clave] = cell(r, cVal);
      }
    }

    final thresholdsJson = <String, dynamic>{
      'version': version,
      'thresholds': thresholds,
      'compression_bands': {
        'domain': bandDomain,
        'source': bandSource ?? _emptySource,
        'bands': bands,
      },
    };
    final archetypesJson = <String, dynamic>{
      'version': version,
      'maps': maps,
    };
    return (
      thresholds: thresholdsJson,
      archetypes: archetypesJson,
      version: version,
    );
  }

  static const Map<String, dynamic> _emptySource = {
    'protocolo': '',
    'rationale': '',
    'reviewed_by': '',
    'reviewed_date': '',
  };

  /// Parsea "15"→int, "0.5"/"7.0"→double (preserva el tipo del JSON original).
  static num _num(String s) {
    final t = s.trim();
    return t.contains('.') ? double.parse(t) : int.parse(t);
  }

  /// Parsea un rango tipo `[0.9, 1.4]`, `(-inf, 0.6)`, `(1.4, +inf)` a
  /// {from, from_inclusive, to, to_inclusive}.
  static Map<String, dynamic> _parseRange(String raw) {
    final s = raw.trim();
    if (s.length < 3 || !s.contains(',')) {
      throw FormatException('Rango de banda inválido: "$raw"');
    }
    final lb = s[0];
    final rb = s[s.length - 1];
    final inner = s.substring(1, s.length - 1).split(',');
    final left = inner[0].trim();
    final right = inner[1].trim();
    return {
      'from': left == '-inf' ? null : double.parse(left),
      'from_inclusive': lb == '[',
      'to': right == '+inf' ? null : double.parse(right),
      'to_inclusive': rb == ']',
    };
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
