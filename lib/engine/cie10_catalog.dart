import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Relación de un diagnóstico CIE-10 con la herida crónica del paciente.
/// Corresponde a la columna RELACION del catálogo reducido.
enum DiagnosisRelation { causa, comorbilidad, consecuencia, herida }

extension DiagnosisRelationX on DiagnosisRelation {
  /// Etiqueta visible (singular).
  String get label {
    switch (this) {
      case DiagnosisRelation.causa:
        return 'Causa';
      case DiagnosisRelation.comorbilidad:
        return 'Comorbilidad';
      case DiagnosisRelation.consecuencia:
        return 'Consecuencia';
      case DiagnosisRelation.herida:
        return 'Herida';
    }
  }

  /// Etiqueta para encabezados de grupo (plural).
  String get pluralLabel {
    switch (this) {
      case DiagnosisRelation.causa:
        return 'Causas';
      case DiagnosisRelation.comorbilidad:
        return 'Comorbilidades';
      case DiagnosisRelation.consecuencia:
        return 'Consecuencias';
      case DiagnosisRelation.herida:
        return 'Heridas';
    }
  }

  /// Valor persistido en Postgres (enum diagnosis_relation) y en el asset.
  String get dbValue => name;

  static DiagnosisRelation fromDb(String s) => DiagnosisRelation.values.firstWhere(
        (e) => e.name == s,
        orElse: () => DiagnosisRelation.comorbilidad,
      );
}

/// Una entrada del catálogo reducido CIE-10 de heridas crónicas
/// (assets/data/cie10_heridas.json). Reference data estática, igual para todos
/// los centros: por eso vive como asset y no en Supabase.
class Cie10Code {
  /// Código CIE-10 (CATALOG_KEY), p.ej. "E119".
  final String code;

  /// Descripción oficial (NOMBRE).
  final String name;

  /// Rol frente a la herida (RELACION).
  final DiagnosisRelation relation;

  /// Agrupador clínico (SUBCATEGORIA), p.ej. "Diabetes mellitus".
  final String subcategory;

  /// Clave del capítulo CIE-10 (romano), p.ej. "IV".
  final String chapterKey;

  /// Nombre del capítulo CIE-10.
  final String chapter;

  /// Nº de caracteres: 3 = rubro/encabezado, 4 = código de hoja (facturable).
  final int chars;

  const Cie10Code({
    required this.code,
    required this.name,
    required this.relation,
    required this.subcategory,
    required this.chapterKey,
    required this.chapter,
    required this.chars,
  });

  bool get isLeaf => chars >= 4;

  factory Cie10Code.fromJson(Map<String, dynamic> json) => Cie10Code(
        code: json['code'] as String,
        name: json['name'] as String,
        relation: DiagnosisRelationX.fromDb(json['relation'] as String),
        subcategory: (json['subcategory'] as String?) ?? '',
        chapterKey: (json['chapterKey'] as String?) ?? '',
        chapter: (json['chapter'] as String?) ?? '',
        chars: (json['chars'] as num?)?.toInt() ?? json['code'].toString().length,
      );
}

/// Quita acentos y pasa a minúsculas para búsqueda insensible a
/// mayúsculas/acentos (el catálogo viene en mayúsculas con acentos).
String _normalize(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final buf = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString();
}

/// Catálogo CIE-10 cargado en memoria desde el asset. Singleton cacheado tras
/// la primera carga (patrón de [KuraPrognosisModel.loadFromAssets]).
class Cie10Catalog {
  final String version;
  final List<Cie10Code> all;

  const Cie10Catalog({required this.version, required this.all});

  static Cie10Catalog? _cached;

  static Future<Cie10Catalog> load({
    String assetPath = 'assets/data/cie10_heridas.json',
  }) async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final codes = ((json['codes'] as List?) ?? const [])
        .map((e) => Cie10Code.fromJson(e as Map<String, dynamic>))
        .toList();
    final catalog = Cie10Catalog(
      version: (json['version'] as String?) ?? '',
      all: codes,
    );
    _cached = catalog;
    return catalog;
  }

  Cie10Code? byCode(String code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return null;
  }

  /// Busca por código o nombre (insensible a mayúsculas/acentos), opcionalmente
  /// filtrando por [relation]. Ordena hojas (chars=4) antes que rubros y por
  /// código. Con [query] vacío devuelve el catálogo (filtrado por relación).
  List<Cie10Code> search(String query, {DiagnosisRelation? relation}) {
    final q = _normalize(query.trim());
    final res = all.where((c) {
      if (relation != null && c.relation != relation) return false;
      if (q.isEmpty) return true;
      return _normalize(c.code).contains(q) ||
          _normalize(c.name).contains(q) ||
          _normalize(c.subcategory).contains(q);
    }).toList();
    res.sort((a, b) {
      // Códigos que empiezan con la query primero (match más relevante).
      if (q.isNotEmpty) {
        final aStarts = _normalize(a.code).startsWith(q);
        final bStarts = _normalize(b.code).startsWith(q);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
      }
      return a.code.compareTo(b.code);
    });
    return res;
  }
}
